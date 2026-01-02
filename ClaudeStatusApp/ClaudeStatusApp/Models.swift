import Foundation

enum ConnectionStatus {
    case connecting
    case connected
    case error
    case noAuth
    case authError
    case tokenExpired
    case apiError
}

struct UsageMetric {
    var used: Int = 0
    var resetTime: String = "Loading..."
}

enum ModelType: String {
    case opus = "O"
    case sonnet = "S"
    case haiku = "H"
}

class UsageData: ObservableObject {
    @Published var session = UsageMetric()
    @Published var weekAll = UsageMetric()
    @Published var weekSonnet = UsageMetric()
    @Published var opusUsage: Int = 0
    @Published var haikuUsage: Int = 0
    @Published var extraUsage: Bool = false
    @Published var lastUpdated: String? = nil
    @Published var status: ConnectionStatus = .connecting
    @Published var activeModel: ModelType = .opus  // Default to Opus
}

struct OAuthCredentials {
    let accessToken: String
    let expiresAt: Double
}
