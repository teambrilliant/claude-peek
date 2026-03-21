import Foundation
import os.log

private let logger = Logger(subsystem: "com.akurkin.claude-peek", category: "FileMapper")

enum SessionFileMapper {
    private static let projectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    /// Find JSONL directly from cwd + sessionId (most reliable)
    static func jsonlPath(cwd: String, sessionId: String) -> URL? {
        let encodedPath = cwd.replacingOccurrences(of: "/", with: "-")
        let projectDir = projectsDir.appendingPathComponent(encodedPath)
        let jsonlFile = projectDir.appendingPathComponent("\(sessionId).jsonl")

        guard FileManager.default.fileExists(atPath: jsonlFile.path) else {
            logger.debug("JSONL not found: \(jsonlFile.path, privacy: .public)")
            return nil
        }

        return jsonlFile
    }
}
