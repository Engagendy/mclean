import Foundation

/// Reports APFS local Time Machine snapshots. Deleted files can stay
/// referenced by snapshots, so freed space may not appear until macOS
/// purges them; surfacing the count explains that to the user.
enum SnapshotService {
    static func localSnapshotCount() async -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runListSnapshots())
            }
        }
    }

    private static func runListSnapshots() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return 0
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return 0
        }
        return output
            .split(separator: "\n")
            .filter { $0.contains("com.apple.TimeMachine") }
            .count
    }
}
