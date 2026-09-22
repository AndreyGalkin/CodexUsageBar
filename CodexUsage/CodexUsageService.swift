import Foundation
import OSLog

@MainActor
final class CodexUsageService: ObservableObject {
    @Published private(set) var limits: RateLimitSnapshot?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false

    private let logger = Logger(subsystem: "com.andreigalkin.CodexUsage", category: "usage")
    private var refreshTask: Task<Void, Never>?
    private var automaticRefreshTask: Task<Void, Never>?

    var statusTitle: String {
        guard let primary = limits?.primary, let secondary = limits?.secondary else { return "Codex —" }
        return "5H \(primary.remainingPercent)% · 7D \(secondary.remainingPercent)%"
    }

    func start() {
        guard automaticRefreshTask == nil else { return }
        refresh()
        automaticRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
                guard let self else { return }
                self.refresh()
            }
        }
    }

    func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { refreshTask = nil; isRefreshing = false }
            do {
                let executable = try Self.locateCodex()
                let response = try await CodexAppServerClient.fetch(executable: executable)
                guard response.rateLimits.primary != nil, response.rateLimits.secondary != nil else {
                    throw CodexUsageError.missingLimits
                }
                limits = response.rateLimits
                lastUpdated = Date()
                errorMessage = nil
                logger.info("Codex rate limits refreshed")
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                logger.error("Rate-limit refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated static func locateCodex(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let explicit = [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ]
        let pathCandidates = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        for path in explicit + pathCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw CodexUsageError.codexNotFound
    }
}

enum CodexAppServerClient {
    static func fetch(executable: URL) async throws -> RateLimitsResponse {
        try await Task.detached(priority: .userInitiated) { try blockingFetch(executable: executable) }.value
    }

    private static func blockingFetch(executable: URL) throws -> RateLimitsResponse {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do { try process.run() } catch { throw CodexUsageError.launchFailed(error.localizedDescription) }
        let deadline = Date().addingTimeInterval(10)
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        try writeJSON([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "CodexUsage", "version": "1.0"],
                "capabilities": ["experimentalApi": true]
            ]
        ], to: input.fileHandleForWriting)

        var buffer = Data()
        while Date() < deadline {
            guard let line = try readLine(from: output.fileHandleForReading, buffer: &buffer, deadline: deadline) else { break }
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if (object["id"] as? Int) == 1 {
                if let error = object["error"] as? [String: Any] {
                    throw CodexUsageError.server(error["message"] as? String ?? "Initialization failed")
                }
                try writeJSON(["method": "initialized"], to: input.fileHandleForWriting)
                try writeJSON(["id": 2, "method": "account/rateLimits/read", "params": NSNull()], to: input.fileHandleForWriting)
                break
            }
        }

        while Date() < deadline {
            guard let line = try readLine(from: output.fileHandleForReading, buffer: &buffer, deadline: deadline) else { break }
            if let response = try RateLimitParser.parseResponseLine(line) { return response }
        }

        let stderr = String(data: errors.fileHandleForReading.availableData, encoding: .utf8) ?? ""
        if stderr.localizedCaseInsensitiveContains("login") || stderr.localizedCaseInsensitiveContains("auth") {
            throw CodexUsageError.notLoggedIn
        }
        if !stderr.isEmpty { throw CodexUsageError.launchFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        throw CodexUsageError.timedOut
    }

    private static func writeJSON(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func readLine(from handle: FileHandle, buffer: inout Data, deadline: Date) throws -> Data? {
        while Date() < deadline {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                return Data(line)
            }
            let chunk = handle.availableData
            if chunk.isEmpty { return buffer.isEmpty ? nil : buffer }
            buffer.append(chunk)
        }
        return nil
    }
}
