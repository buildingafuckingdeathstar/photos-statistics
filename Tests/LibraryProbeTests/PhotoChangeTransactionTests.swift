import XCTest
@testable import LibraryProbe

final class PhotoChangeTransactionTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        private var backgroundOnly = true
        func append(_ value: String) {
            lock.lock()
            defer { lock.unlock() }
            values.append(value)
            backgroundOnly = backgroundOnly && !Thread.isMainThread
        }
        func snapshot() -> ([String], Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (values, backgroundOnly)
        }
    }

    /// Reproduces the execution pattern in the crash report: a MainActor caller
    /// submits three changes, and PhotoKit runs the block on a background queue.
    /// The injected submitter never accesses the real Photos library.
    @MainActor
    func testThreePhotoApprovalRunsOffMainAndReturnsToMainActor() async throws {
        let recorder = Recorder()
        try await PhotoChangeTransaction.perform(assets: ["one", "two", "three"], change: { value in
            recorder.append(value)
        }, submit: { changes, completion in
            DispatchQueue(label: "photos-statistics.test.transaction").async {
                changes()
                completion(true, nil)
            }
        })
        MainActor.preconditionIsolated()
        let (values, backgroundOnly) = recorder.snapshot()
        XCTAssertEqual(values, ["one", "two", "three"])
        XCTAssertTrue(backgroundOnly)
    }

    @MainActor
    func testFailedTransactionPropagatesPhotosError() async {
        do {
            try await PhotoChangeTransaction.perform(assets: ["one"], change: { _ in
                XCTFail("A rejected transaction must not run the change block")
            }, submit: { _, completion in
                DispatchQueue.global().async {
                    completion(false, NSError(domain: "PhotosTest", code: 42))
                }
            })
            XCTFail("Expected failure")
        } catch {
            MainActor.preconditionIsolated()
            XCTAssertEqual((error as NSError).domain, "PhotosTest")
            XCTAssertEqual((error as NSError).code, 42)
        }
    }

    @MainActor
    func testFailureWithoutAnErrorStillReturnsFailure() async {
        do {
            try await PhotoChangeTransaction.perform(assets: ["one"], change: { _ in }, submit: { _, completion in
                DispatchQueue.global().async { completion(false, nil) }
            })
            XCTFail("Expected failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("did not complete"))
        }
    }
}
