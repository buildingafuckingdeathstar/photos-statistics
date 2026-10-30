import Foundation

/// PhotoKit invokes change blocks and completion handlers on its own queues.
/// Explicit Sendable callbacks prevent accidental inheritance of a caller's
/// MainActor isolation. UI state must only be updated after awaiting this method.
public enum PhotoChangeTransaction {
    public typealias Completion = @Sendable (Bool, (any Error)?) -> Void
    public typealias Submission = @Sendable (@escaping @Sendable () -> Void, @escaping Completion) -> Void

    public nonisolated static func perform<Asset: Sendable>(
        assets: [Asset],
        change: @escaping @Sendable (Asset) -> Void,
        submit: Submission
    ) async throws {
        let changes: @Sendable () -> Void = {
            for asset in assets { change(asset) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            submit(changes) { success, error in
                if success { continuation.resume() }
                else {
                    continuation.resume(throwing: error ?? ProbeFailure(message: "Photos did not complete the location update."))
                }
            }
        }
    }
}
