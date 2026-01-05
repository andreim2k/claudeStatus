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

enum SubscriptionType: String {
    case free = "free"
    case pro = "pro"
    case max = "max"

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .max: return "Max"
        }
    }

    // Free: Sonnet only | Pro: Sonnet + Opus | Max: All models
    var hasOpusAccess: Bool {
        return self == .pro || self == .max
    }

    // Only Max has separate per-model weekly limits (Sonnet, Opus, Haiku)
    var hasSeparateModelLimits: Bool {
        return self == .max
    }

    // All paid plans have session (5-hour) limits
    var hasSessionLimit: Bool {
        return true  // All plans have this
    }

    // All plans have weekly limits
    var hasWeeklyLimit: Bool {
        return true  // All plans have this
    }
}

class UsageData: ObservableObject {
    @Published var session = UsageMetric()
    @Published var weekAll = UsageMetric()
    @Published var weekSonnet = UsageMetric()
    @Published var opusUsage: Int = 0
    @Published var haikuUsage: Int = 0
    @Published var extraUsage: Bool = false
    @Published var extraUsageAmount: Double = 0.0  // Extra usage in dollars
    @Published var extraUsagePercent: Int = 0  // Extra usage percentage
    @Published var lastUpdated: String? = nil
    @Published var status: ConnectionStatus = .connecting
    @Published var activeModel: ModelType = .sonnet  // Default to Sonnet (works for all plans)
    @Published var subscriptionType: SubscriptionType = .free  // Default to Free until detected
}

struct OAuthCredentials {
    let accessToken: String
    let expiresAt: Double
}
