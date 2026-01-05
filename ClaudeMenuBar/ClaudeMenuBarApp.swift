import SwiftUI
import AppKit

@main
struct ClaudeMenuBarApp: App {
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
    var updateTimer: Timer?
    var uiUpdateTimer: Timer?
    var sessionResetTimestamp: String?
    var weeklyResetTimestamp: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        detectCurrentModel()
        startUpdateTimer()
        fetchUsageDataAsync()
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
        popover.contentSize = NSSize(width: 320, height: 650)
        popover.behavior = .transient
        popover.animates = true

        let hostingController = NSHostingController(rootView: StatusPopoverView(appDelegate: self, usageData: usageData))
        popover.contentViewController = hostingController
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
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
            usageString = "\(sessionPct)% · \(expiryTime) ⋮ \(weekAllPct)% ⋮ \(sonnetPct)% · \(weeklyExpiryTime)"
        } else {
            usageString = "\(sessionPct)% · \(expiryTime) ⋮ \(weekAllPct)% · \(weeklyExpiryTime)"
        }

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
        // Fetch data every 5 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
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

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let resetDate = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) else {
            return "--"
        }

        let now = Date()
        let remaining = resetDate.timeIntervalSince(now)

        if remaining <= 0 {
            return "0m"
        }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours >= 1 {
            if minutes == 0 {
                return "\(hours)h"
            } else if minutes < 30 {
                return ">\(hours)h"
            } else {
                return "<\(hours + 1)h"
            }
        } else {
            return "\(minutes)m"
        }
    }

    func getWeeklyExpiryTime() -> String {
        guard let timestamp = weeklyResetTimestamp else { return "--" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let resetDate = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) else {
            return "--"
        }

        let now = Date()
        let remaining = resetDate.timeIntervalSince(now)

        if remaining <= 0 {
            return "0m"
        }

        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if days >= 1 {
            if hours == 0 {
                return "\(days)d"
            } else if hours < 12 {
                return ">\(days)d"
            } else {
                return "<\(days + 1)d"
            }
        }

        if hours >= 1 {
            if minutes == 0 {
                return "\(hours)h"
            } else if minutes < 30 {
                return ">\(hours)h"
            } else {
                return "<\(hours + 1)h"
            }
        }

        if seconds == 0 {
            return "\(minutes)m"
        } else if seconds < 30 {
            return ">\(minutes)m"
        } else {
            return "<\(minutes + 1)m"
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
            DispatchQueue.main.async {
                self.usageData.status = .noAuth
                self.updateStatusButton()
            }
            return
        }

        if Date().timeIntervalSince1970 > creds.expiresAt {
            DispatchQueue.main.async {
                self.usageData.status = .tokenExpired
                self.updateStatusButton()
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

            DispatchQueue.main.async {
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

                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                self.usageData.lastUpdated = formatter.string(from: Date())
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

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) else {
            return "Unknown"
        }

        let timeZone = TimeZone.current
        let tzName = timeZone.identifier

        let timeFormatter = DateFormatter()
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: date)

        return "Resets \(timeStr) (\(tzName))"
    }

    func formatWeeklyResetTime(_ isoTimestamp: String?) -> String {
        guard let timestamp = isoTimestamp else { return "Unknown" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) else {
            return "Unknown"
        }

        let timeZone = TimeZone.current
        let tzName = timeZone.identifier

        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "MMM d, HH:mm"

        return "Resets \(dateFormatter.string(from: date)) (\(tzName))"
    }

    func manualRefresh() {
        detectCurrentModel()
        fetchUsageDataAsync()
    }
}
