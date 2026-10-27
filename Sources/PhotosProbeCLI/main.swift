import Foundation
import LibraryProbe
import Darwin

let arguments = Array(CommandLine.arguments.dropFirst())
let usage = """
Usage: photos-probe /path/to/Photos\u{0020}Library.photoslibrary

Quote paths containing spaces. A folder containing Photos.sqlite is also accepted.
Reads library metadata only; does not open images or download iCloud originals.
This command-line check does not test Mac App Store sandbox permissions.
"""

if arguments == ["--help"] || arguments == ["-h"] {
    print(usage)
    exit(EXIT_SUCCESS)
}
guard arguments.count == 1, !arguments[0].hasPrefix("-") else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}
let path = (arguments[0] as NSString).expandingTildeInPath
do {
    let report = try LibraryProbe.inspect(selection: URL(fileURLWithPath: path))
    print("Execution: command-line utility (not an App Sandbox access test)\n")
    print(report.text)
} catch {
    FileHandle.standardError.write(Data(("Probe failed: \(error.localizedDescription)\n").utf8))
    exit(EXIT_FAILURE)
}
