import Foundation

struct RateLimitWindow: Codable, Equatable, Sendable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?

    var remainingPercent: Int { min(100, max(0, 100 - usedPercent)) }
    var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
}

struct RateLimitSnapshot: Codable, Equatable, Sendable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

struct RateLimitsResponse: Codable, Equatable, Sendable {
    let rateLimits: RateLimitSnapshot
}

enum RateLimitParser {
    static func parseResponseLine(_ data: Data, expectedID: Int = 2) throws -> RateLimitsResponse? {
        let envelope = try JSONDecoder().decode(JSONRPCEnvelope.self, from: data)
        guard envelope.id == expectedID else { return nil }
        if let error = envelope.error { throw CodexUsageError.server(error.message) }
        guard let result = envelope.result else { throw CodexUsageError.malformedResponse }
        return result
    }

    private struct JSONRPCEnvelope: Decodable {
        let id: Int?
        let result: RateLimitsResponse?
        let error: RPCError?
    }

    private struct RPCError: Decodable { let message: String }
}

enum CodexUsageError: LocalizedError, Equatable {
    case codexNotFound
    case launchFailed(String)
    case notLoggedIn
    case server(String)
    case malformedResponse
    case missingLimits
    case timedOut

    var errorDescription: String? {
        switch self {
        case .codexNotFound: "Codex was not found. Install it or add it to PATH."
        case .launchFailed(let message): "Codex app-server failed: \(message)"
        case .notLoggedIn: "Codex is not logged in. Open Codex and sign in."
        case .server(let message): "Codex reported: \(message)"
        case .malformedResponse: "Codex returned an unexpected response."
        case .missingLimits: "Codex did not return both usage windows."
        case .timedOut: "Codex app-server timed out."
        }
    }
}
