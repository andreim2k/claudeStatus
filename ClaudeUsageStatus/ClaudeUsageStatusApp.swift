import SwiftUI
import AppKit

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    @Published var usageData = UsageData()
    @Published var isPopoverVisible = false  // Track popover visibility for animations
    var updateTimer: Timer?
    var uiUpdateTimer: Timer?
    var sessionResetTimestamp: String?
    var weeklyResetTimestamp: String?

    // MARK: - Cached formatters (avoid recreating on every call)
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FallbackFormatter = ISO8601DateFormatter()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let resetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weeklyResetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()

    // MARK: - Cached attributed string components (avoid recreating every second)
    private var cachedAttributedTitle: NSAttributedString?
    private var lastModelSymbol: String?
    private var lastUsageString: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        detectCurrentModel()
        startUpdateTimer()
        fetchUsageDataAsync()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up timers to prevent memory leaks
        updateTimer?.invalidate()
        updateTimer = nil
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = nil

        // Clear popover content
        popover?.contentViewController = nil
    }

    deinit {
        updateTimer?.invalidate()
        uiUpdateTimer?.invalidate()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            updateStatusButton()
        }
    }

    func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 750)
        popover.behavior = .transient
        popover.animates = true

        let hostingController = NSHostingController(rootView: StatusPopoverView(appDelegate: self, usageData: usageData))
        popover.contentViewController = hostingController
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
                isPopoverVisible = false  // Track for animation pausing
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
                isPopoverVisible = true  // Track for animation pausing
            }
        }
    }

    func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let activeModel = usageData.activeModel
        let isConnected = usageData.status == .connected

        // Get model symbol (circled letter)
        let modelSymbol: String
        if isConnected {
            switch activeModel {
            case .opus: modelSymbol = "Ⓞ"
            case .sonnet: modelSymbol = "Ⓢ"
            case .haiku: modelSymbol = "Ⓗ"
            }
        } else {
            modelSymbol = "⊗"
        }

        // Get times
        let expiryTime = getSessionExpiryTime()
        let weeklyExpiryTime = getWeeklyExpiryTime()
        let subscriptionType = usageData.subscriptionType

        // Build usage text
        let sessionPct = isConnected ? "\(usageData.session.used)" : "--"
        let weekAllPct = isConnected ? "\(usageData.weekAll.used)" : "--"

        let usageString: String
        if subscriptionType.hasSeparateModelLimits && activeModel == .sonnet {
            let sonnetPct = isConnected ? "\(usageData.weekSonnet.used)" : "--"
            usageString = "\(sessionPct)% ~ \(expiryTime) | \(weekAllPct)% ~ \(weeklyExpiryTime) | \(sonnetPct)% ~ \(weeklyExpiryTime)"
        } else {
            usageString = "\(sessionPct)% ~ \(expiryTime) | \(weekAllPct)% ~ \(weeklyExpiryTime)"
        }

        // Only recreate attributed string if values changed (avoid memory churn)
        if modelSymbol == lastModelSymbol && usageString == lastUsageString,
           let cached = cachedAttributedTitle {
            button.attributedTitle = cached
            return
        }

        // Cache the new values
        lastModelSymbol = modelSymbol
        lastUsageString = usageString

        // Create attributed string with different sizes
        let attributed = NSMutableAttributedString()

        // Circled letter - larger size (24pt with baseline offset)
        let circleLetter = NSAttributedString(string: "\(modelSymbol) ", attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .baselineOffset: -3
        ])
        attributed.append(circleLetter)

        // Usage text - menu bar font
        let usageText = NSAttributedString(string: usageString, attributes: [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor
        ])
        attributed.append(usageText)

        // Cache and apply
        cachedAttributedTitle = attributed
        button.attributedTitle = attributed
    }

    func detectCurrentModel() {
        detectSubscriptionType()

        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        if let settingsData = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
           let settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any],
           let modelStr = settings["model"] as? String {
            switch modelStr.lowercased() {
            case "opus":
                usageData.activeModel = .opus
                return
            case "sonnet":
                usageData.activeModel = .sonnet
                return
            case "haiku":
                usageData.activeModel = .haiku
                return
            default:
                break
            }
        }

        let modelFilePath = NSHomeDirectory() + "/.claude-status-model"
        if let content = try? String(contentsOfFile: modelFilePath, encoding: .utf8) {
            let modelStr = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch modelStr {
            case "opus", "o":
                usageData.activeModel = .opus
                return
            case "sonnet", "s":
                usageData.activeModel = .sonnet
                return
            case "haiku", "h":
                usageData.activeModel = .haiku
                return
            default:
                break
            }
        }

        setDefaultModelForSubscription()
    }

    func detectSubscriptionType() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any] else {
            usageData.subscriptionType = .free
            return
        }

        if let subType = oauth["subscriptionType"] as? String {
            switch subType.lowercased() {
            case "max":
                usageData.subscriptionType = .max
            case "pro":
                usageData.subscriptionType = .pro
            default:
                usageData.subscriptionType = .free
            }
        } else {
            usageData.subscriptionType = .free
        }
    }

    func setDefaultModelForSubscription() {
        switch usageData.subscriptionType {
        case .free:
            usageData.activeModel = .sonnet
        case .pro:
            usageData.activeModel = .sonnet
        case .max:
            usageData.activeModel = .opus
        }
    }

    func startUpdateTimer() {
        // Fetch data every 60 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.detectCurrentModel()
            self.fetchUsageDataAsync()
        }

        // Update UI every 1 second for smooth countdown
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateStatusButton()
        }
    }

    func getSessionExpiryTime() -> String {
        guard let timestamp = sessionResetTimestamp else { return "--" }

        // Use cached formatters instead of creating new ones
        guard let resetDate = Self.iso8601Formatter.date(from: timestamp)
                ?? Self.iso8601FallbackFormatter.date(from: timestamp) else {
            return "--"
        }

        let now = Date()
        let remaining = resetDate.timeIntervalSince(now)

        if remaining <= 0 {
            return "0m"
        }

        let totalHours = remaining / 3600.0
        let totalMinutes = remaining / 60.0

        // If >= 1 hour, show as decimal hours (e.g., 3.5h)
        if totalHours >= 1 {
            return String(format: "%.1fh", totalHours)
        } else {
            // Less than 1 hour, show minutes
            return "\(Int(totalMinutes))m"
        }
    }

    func getWeeklyExpiryTime() -> String {
        guard let timestamp = weeklyResetTimestamp else { return "--" }

        // Use cached formatters instead of creating new ones
        guard let resetDate = Self.iso8601Formatter.date(from: timestamp)
                ?? Self.iso8601FallbackFormatter.date(from: timestamp) else {
            return "--"
        }

        let now = Date()
        let remaining = resetDate.timeIntervalSince(now)

        if remaining <= 0 {
            return "0m"
        }

        let totalDays = remaining / 86400.0
        let totalHours = remaining / 3600.0
        let totalMinutes = remaining / 60.0

        // If >= 1 day, show as decimal days (e.g., 2.5d)
        if totalDays >= 1 {
            return String(format: "%.1fd", totalDays)
        }
        // If >= 1 hour, show as decimal hours (e.g., 18.5h)
        else if totalHours >= 1 {
            return String(format: "%.1fh", totalHours)
        }
        // Less than 1 hour, show minutes
        else {
            return "\(Int(totalMinutes))m"
        }
    }

    func getCredentials() -> OAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              let expiresAt = oauth["expiresAt"] as? Double else {
            return nil
        }

        return OAuthCredentials(accessToken: accessToken, expiresAt: expiresAt / 1000)
    }

    func fetchUsageDataAsync() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.fetchUsageData()
        }
    }

    func fetchUsageData() {
        guard let creds = getCredentials() else {
            DispatchQueue.main.async { [weak self] in
                self?.usageData.status = .noAuth
                self?.updateStatusButton()
            }
            return
        }

        if Date().timeIntervalSince1970 > creds.expiresAt {
            DispatchQueue.main.async { [weak self] in
                self?.usageData.status = .tokenExpired
                self?.updateStatusButton()
            }
            return
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if error != nil {
                    self.usageData.status = .error
                    self.updateStatusButton()
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.usageData.status = .error
                    self.updateStatusButton()
                    return
                }

                if httpResponse.statusCode == 200, let data = data {
                    self.parseAPIResponse(data)
                    self.usageData.status = .connected
                } else if httpResponse.statusCode == 401 {
                    self.usageData.status = .authError
                } else {
                    self.usageData.status = .apiError
                }

                // Use cached formatter instead of creating a new one
                self.usageData.lastUpdated = Self.timeFormatter.string(from: Date())
                self.updateStatusButton()
            }
        }.resume()
    }

    func parseAPIResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let fiveHour = json["five_hour"] as? [String: Any] {
            if let utilization = fiveHour["utilization"] as? Double {
                usageData.session.used = Int(utilization)
            }
            sessionResetTimestamp = fiveHour["resets_at"] as? String
            usageData.session.resetTime = formatSessionResetTime(fiveHour["resets_at"] as? String)
        }

        if let sevenDay = json["seven_day"] as? [String: Any] {
            if let utilization = sevenDay["utilization"] as? Double {
                usageData.weekAll.used = Int(utilization)
            }
            weeklyResetTimestamp = sevenDay["resets_at"] as? String
            usageData.weekAll.resetTime = formatWeeklyResetTime(sevenDay["resets_at"] as? String)
        }

        if let sonnet = json["seven_day_sonnet"] as? [String: Any] {
            if let utilization = sonnet["utilization"] as? Double {
                usageData.weekSonnet.used = Int(utilization)
            }
            usageData.weekSonnet.resetTime = formatWeeklyResetTime(sonnet["resets_at"] as? String)
        } else {
            usageData.weekSonnet.used = 0
            usageData.weekSonnet.resetTime = "No separate limit"
        }

        if let opus = json["seven_day_opus"] as? [String: Any] {
            if let utilization = opus["utilization"] as? Double {
                usageData.opusUsage = Int(utilization)
            }
        } else {
            usageData.opusUsage = 0
        }

        if let haiku = json["seven_day_haiku"] as? [String: Any] {
            if let utilization = haiku["utilization"] as? Double {
                usageData.haikuUsage = Int(utilization)
            }
        } else {
            usageData.haikuUsage = 0
        }

        if let extraUsage = json["extra_usage"] as? [String: Any] {
            usageData.extraUsage = extraUsage["is_enabled"] as? Bool ?? false
            usageData.extraUsageAmount = extraUsage["amount_usd"] as? Double ?? 0.0
            if let utilization = extraUsage["utilization"] as? Double {
                usageData.extraUsagePercent = Int(utilization)
            } else {
                usageData.extraUsagePercent = 0
            }
        } else {
            usageData.extraUsage = false
            usageData.extraUsageAmount = 0.0
            usageData.extraUsagePercent = 0
        }
    }

    func formatSessionResetTime(_ isoTimestamp: String?) -> String {
        guard let timestamp = isoTimestamp else { return "Unknown" }

        // Use cached formatters instead of creating new ones
        guard let date = Self.iso8601Formatter.date(from: timestamp)
                ?? Self.iso8601FallbackFormatter.date(from: timestamp) else {
            return "Unknown"
        }

        let timeZone = TimeZone.current
        let tzName = timeZone.identifier

        // Update timezone on cached formatter (thread-safe for main thread usage)
        Self.resetTimeFormatter.timeZone = timeZone
        let timeStr = Self.resetTimeFormatter.string(from: date)

        return "Resets \(timeStr) (\(tzName))"
    }

    func formatWeeklyResetTime(_ isoTimestamp: String?) -> String {
        guard let timestamp = isoTimestamp else { return "Unknown" }

        // Use cached formatters instead of creating new ones
        guard let date = Self.iso8601Formatter.date(from: timestamp)
                ?? Self.iso8601FallbackFormatter.date(from: timestamp) else {
            return "Unknown"
        }

        let timeZone = TimeZone.current
        let tzName = timeZone.identifier

        // Update timezone on cached formatter (thread-safe for main thread usage)
        Self.weeklyResetFormatter.timeZone = timeZone

        return "Resets \(Self.weeklyResetFormatter.string(from: date)) (\(tzName))"
    }

    func manualRefresh() {
        detectCurrentModel()
        fetchUsageDataAsync()
    }
}
