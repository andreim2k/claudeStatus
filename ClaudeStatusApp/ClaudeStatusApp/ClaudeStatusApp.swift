import SwiftUI
import AppKit

@main
struct ClaudeStatusApp: App {
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
    var credentialsCache: OAuthCredentials?
    var credentialsCacheTime: Date?
    var sessionResetTimestamp: String?  // Store raw timestamp for menu bar display

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        detectCurrentModel()  // Detect model on startup
        startUpdateTimer()
        fetchUsageDataAsync()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.image = nil  // No icon
            button.font = NSFont.systemFont(ofSize: 11, weight: .regular)

            // Create attributed string with different sizes
            let attributed = NSMutableAttributedString()

            // Circled letter (much larger) - start with circled times since we're connecting
            let circleLetter = NSAttributedString(string: "⊗ ", attributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .baselineOffset: -3
            ])
            attributed.append(circleLetter)

            // Usage text with middle-dot separators
            let usageText = NSAttributedString(string: "--% -- · --% · --%", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .baselineOffset: 0
            ])
            attributed.append(usageText)

            button.attributedTitle = attributed
        }
    }

    // Detect current model from Claude Code settings or subscription type
    func detectCurrentModel() {
        // First check Claude Code settings.json
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

        // Fallback: check manual override file
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

        // Final fallback: detect from subscription type
        detectModelFromSubscription()
    }

    // Detect default model based on subscription type from keychain
    func detectModelFromSubscription() {
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
            usageData.activeModel = .opus  // Default fallback
            return
        }

        // Check subscription type to determine default model
        if let subscriptionType = oauth["subscriptionType"] as? String {
            switch subscriptionType.lowercased() {
            case "max":
                usageData.activeModel = .opus  // Max users default to Opus
            case "pro":
                usageData.activeModel = .sonnet  // Pro users default to Sonnet
            default:
                usageData.activeModel = .sonnet  // Free/other default to Sonnet
            }
        } else {
            usageData.activeModel = .opus
        }
    }

    func createClaudeIcon() -> NSImage? {
        // Try to load the Claude.ai favicon from Resources
        if let bundlePath = Bundle.main.resourcePath,
           let image = NSImage(contentsOfFile: bundlePath + "/claude-icon@2x.png") {
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true  // Makes it white/adaptive to menu bar theme
            return image
        }

        // Fallback to SF Symbol if icon file not found
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Claude")
        image?.isTemplate = true
        return image?.withSymbolConfiguration(config)
    }

    func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 650)
        popover.behavior = .transient  // Closes when clicking outside
        popover.animates = true

        let hostingController = NSHostingController(rootView: StatusPopoverView(appDelegate: self, usageData: usageData))
        popover.contentViewController = hostingController

        // Ensure popover closes on outside click
        popover.setValue(true, forKey: "shouldHideAnchor")
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Activate the app to ensure proper focus handling
                NSApp.activate(ignoringOtherApps: true)

                // Make sure the popover window accepts mouse events
                if let popoverWindow = popover.contentViewController?.view.window {
                    popoverWindow.makeKey()
                }
            }
        }
    }

    func startUpdateTimer() {
        // Update every 5 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.detectCurrentModel()  // Re-detect model on each refresh
            self.fetchUsageDataAsync()
        }

        // Also update UI every second for smooth updates
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateStatusButton()
        }
    }

    func updateStatusButton() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let button = self.statusItem.button else { return }

            let activeModel = self.usageData.activeModel
            let isConnected = self.usageData.status == .connected

            // Show "--" when not connected, remaining percentage when connected
            let cs = isConnected ? "\(100 - self.usageData.session.used)" : "--"
            let cw = isConnected ? "\(100 - self.usageData.weekAll.used)" : "--"
            let cws = isConnected ? "\(100 - self.usageData.weekSonnet.used)" : "--"

            // Get model symbol (circled letter) - show empty circle when not connected
            let modelSymbol: String
            if isConnected {
                switch activeModel {
                case .opus: modelSymbol = "Ⓞ"      // Circled O
                case .sonnet: modelSymbol = "Ⓢ"    // Circled S
                case .haiku: modelSymbol = "Ⓗ"     // Circled H
                }
            } else {
                modelSymbol = "⊗"  // Circled times when not connected
            }

            // Create attributed string with different sizes
            let attributed = NSMutableAttributedString()

            // Circled letter (much larger, 24pt)
            let circleLetter = NSAttributedString(string: "\(modelSymbol) ", attributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .baselineOffset: -3
            ])
            attributed.append(circleLetter)

            // Get session expiry time
            let expiryTime = self.getSessionExpiryTime()

            // Usage text with middle-dot separators
            let usageText = NSAttributedString(string: "\(cs)% \(expiryTime) · \(cw)% · \(cws)%", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .baselineOffset: 0
            ])
            attributed.append(usageText)

            button.attributedTitle = attributed
        }
    }

    func getStatusIcon() -> String {
        let maxUsage = max(usageData.session.used, usageData.weekAll.used, usageData.weekSonnet.used)

        switch usageData.status {
        case .connecting: return "◌"
        case .error, .noAuth, .authError: return "◍"
        case .connected:
            if maxUsage >= 90 { return "◉" }
            else if maxUsage >= 70 { return "◕" }
            else if maxUsage >= 50 { return "◑" }
            else if maxUsage >= 25 { return "◔" }
            else { return "○" }
        default: return "◌"
        }
    }

    func getCredentials() -> OAuthCredentials? {
        if let cache = credentialsCache,
           let cacheTime = credentialsCacheTime,
           Date().timeIntervalSince(cacheTime) < 300 {
            return cache
        }

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

        let creds = OAuthCredentials(accessToken: accessToken, expiresAt: expiresAt / 1000)
        credentialsCache = creds
        credentialsCacheTime = Date()
        return creds
    }

    func fetchUsageDataAsync() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.fetchUsageData()
        }
    }

    func fetchUsageData() {
        guard let creds = getCredentials() else {
            DispatchQueue.main.async { self.usageData.status = .noAuth }
            return
        }

        if Date().timeIntervalSince1970 > creds.expiresAt {
            DispatchQueue.main.async { self.usageData.status = .tokenExpired }
            credentialsCache = nil
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
                if let error = error {
                    self.usageData.status = .error
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.usageData.status = .error
                    return
                }

                if httpResponse.statusCode == 200, let data = data {
                    self.parseAPIResponse(data)
                    self.usageData.status = .connected
                } else if httpResponse.statusCode == 401 {
                    self.usageData.status = .authError
                    self.credentialsCache = nil
                } else {
                    self.usageData.status = .apiError
                }

                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                self.usageData.lastUpdated = formatter.string(from: Date())
            }
        }.resume()
    }

    func parseAPIResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let fiveHour = json["five_hour"] as? [String: Any] {
            if let utilization = fiveHour["utilization"] as? Double {
                usageData.session.used = Int(utilization)
            }
            sessionResetTimestamp = fiveHour["resets_at"] as? String  // Store for menu bar
            usageData.session.resetTime = formatSessionResetTime(fiveHour["resets_at"] as? String)
        }

        if let sevenDay = json["seven_day"] as? [String: Any] {
            if let utilization = sevenDay["utilization"] as? Double {
                usageData.weekAll.used = Int(utilization)
            }
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

        // Parse Opus usage (if available)
        if let opus = json["seven_day_opus"] as? [String: Any] {
            if let utilization = opus["utilization"] as? Double {
                usageData.opusUsage = Int(utilization)
            }
        } else {
            usageData.opusUsage = 0
        }

        // Parse Haiku usage (if available)
        if let haiku = json["seven_day_haiku"] as? [String: Any] {
            if let utilization = haiku["utilization"] as? Double {
                usageData.haikuUsage = Int(utilization)
            }
        } else {
            usageData.haikuUsage = 0
        }

        if let extraUsage = json["extra_usage"] as? [String: Any] {
            usageData.extraUsage = extraUsage["is_enabled"] as? Bool ?? false
        }
    }

    // For session reset - just show time in 24h format (e.g., "Resets 00:00 (Europe/Bucharest)")
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

    // For weekly reset - show date and time in 24h format (e.g., "Resets Jan 8, 17:00 (Europe/Bucharest)")
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

    // Get remaining time until session resets (e.g., ">2h", "<3h", "2h", or "45m")
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
                return "\(hours)h"       // Exactly X hours
            } else if minutes < 30 {
                return ">\(hours)h"      // More than X hours (just passed the hour)
            } else {
                return "<\(hours + 1)h"  // Less than X+1 hours (approaching next hour)
            }
        } else {
            return "\(minutes)m"         // Less than 1 hour, show minutes
        }
    }

    func manualRefresh() {
        statusItem.button?.title = "◌ ..."
        credentialsCache = nil
        detectCurrentModel()  // Re-detect model on refresh
        fetchUsageDataAsync()
    }
}
