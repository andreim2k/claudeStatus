import SwiftUI
import Darwin

struct StatusPopoverView: View {
    @ObservedObject var appDelegate: AppDelegate
    @ObservedObject var usageData: UsageData

    var activeModelName: String {
        switch usageData.activeModel {
        case .opus: return "claude-opus-4-5"
        case .sonnet: return "claude-sonnet-4-5"
        case .haiku: return "claude-haiku-4-5"
        }
    }

    var modelSpecificTitle: String {
        // Always show Sonnet for Max (API returns seven_day_sonnet)
        return "Current Week (Sonnet)"
    }

    var modelSpecificUsage: Int {
        // Always show Sonnet usage for Max
        return usageData.weekSonnet.used
    }

    var modelSpecificResetTime: String {
        return usageData.weekSonnet.resetTime  // Same reset time for all models
    }

    var body: some View {
        ZStack {
            // Liquid glass background (pauses animations when popover is hidden)
            LiquidGlassBackground(isVisible: appDelegate.isPopoverVisible)

            VStack(spacing: 0) {
                // Header with model and subscription indicator
                HeaderView(
                    currentModel: activeModelName,
                    subscriptionType: usageData.subscriptionType
                )

                ScrollView {
                    VStack(spacing: 16) {
                        // Usage cards (show used %)
                        UsageCardView(
                            title: "Current 5h Session",
                            subtitle: "used",
                            percentage: usageData.session.used,
                            resetTime: usageData.session.resetTime,
                            gradient: Gradient(colors: [.cyan, .blue])
                        )

                        UsageCardView(
                            title: "Current Week (all models)",
                            subtitle: "used",
                            percentage: usageData.weekAll.used,
                            resetTime: usageData.weekAll.resetTime,
                            gradient: Gradient(colors: [.purple, .pink])
                        )

                        // Only show model-specific weekly limit for Max plan
                        if usageData.subscriptionType.hasSeparateModelLimits {
                            UsageCardView(
                                title: modelSpecificTitle,
                                subtitle: "used",
                                percentage: modelSpecificUsage,
                                resetTime: modelSpecificResetTime,
                                gradient: Gradient(colors: [.orange, .red])
                            )
                        }

                        // Extra usage - show as card if enabled, otherwise badge
                        if usageData.extraUsage {
                            UsageCardView(
                                title: "Extra Usage",
                                subtitle: "$\(String(format: "%.2f", usageData.extraUsageAmount))",
                                percentage: usageData.extraUsagePercent,
                                resetTime: "Pay-per-use beyond plan limits",
                                gradient: Gradient(colors: [.yellow, .orange])
                            )
                        } else {
                            ExtraUsageBadge(isEnabled: usageData.extraUsage, amount: usageData.extraUsageAmount)
                        }

                        // Status footer
                        StatusFooterView(
                            lastUpdated: usageData.lastUpdated,
                            status: usageData.status
                        )
                    }
                    .padding(16)
                }

                // Action buttons fixed at bottom
                VStack(spacing: 0) {
                    Divider()
                    ActionButtonsView(
                        onRefresh: { [weak appDelegate] in appDelegate?.manualRefresh() },
                        onQuit: { NSApp.terminate(nil) }
                    )
                    .padding(12)
                }
                .background(.ultraThinMaterial)
            }
        }
        .frame(width: 320, height: usageData.subscriptionType.hasSeparateModelLimits ? 750 : 650)
    }
}

// MARK: - Liquid Glass Background

struct LiquidGlassBackground: View {
    let isVisible: Bool  // Control animations based on visibility

    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.95),
                    Color(nsColor: .controlBackgroundColor).opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Animated blobs for liquid effect (only animate when visible)
            GeometryReader { geo in
                ZStack {
                    LiquidBlob(color: .cyan.opacity(0.15), size: 150, isAnimating: isVisible)
                        .offset(x: -50, y: -30)

                    LiquidBlob(color: .purple.opacity(0.12), size: 180, isAnimating: isVisible)
                        .offset(x: geo.size.width - 80, y: 100)

                    LiquidBlob(color: .pink.opacity(0.1), size: 120, isAnimating: isVisible)
                        .offset(x: 30, y: geo.size.height - 150)
                }
            }

            // Glass overlay
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
}

struct LiquidBlob: View {
    let color: Color
    let size: CGFloat
    let isAnimating: Bool  // Control animation state
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 40)
            .scaleEffect(animate ? 1.1 : 0.9)
            .animation(
                isAnimating ? .easeInOut(duration: 4).repeatForever(autoreverses: true) : .default,
                value: animate
            )
            .onChange(of: isAnimating) { _, newValue in
                // Only animate when visible to save CPU/GPU resources
                animate = newValue
            }
            .onAppear {
                // Start animation only if visible
                animate = isAnimating
            }
    }
}

// MARK: - Header

struct HeaderView: View {
    let currentModel: String
    let subscriptionType: SubscriptionType

    var subscriptionColor: Color {
        switch subscriptionType {
        case .max: return .purple
        case .pro: return .blue
        case .free: return .gray
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                // Claude.ai colored icon
                if let nsImage = loadClaudeColoredIcon() {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    // Fallback to sparkle
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("Claude Status")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Subscription badge
                Text(subscriptionType.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(subscriptionColor)
                    )
            }

            // Current model indicator
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.caption)
                    .foregroundColor(.orange)

                Text("Active Model:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(currentModel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Usage Card

struct UsageCardView: View {
    let title: String
    let subtitle: String
    let percentage: Int
    let resetTime: String
    let gradient: Gradient

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Percentage badge
                Text("\(percentage)%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
                    )
            }

            // Progress bar
            GlassProgressBar(percentage: percentage, gradient: gradient)

            // Reset time
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(resetTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Glass Progress Bar

struct GlassProgressBar: View {
    let percentage: Int
    let gradient: Gradient

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))

                // Filled portion
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * CGFloat(percentage) / 100)

                // Glass highlight
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: geo.size.height / 2)
                    .offset(y: -geo.size.height / 4)
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Extra Usage Badge

struct ExtraUsageBadge: View {
    let isEnabled: Bool
    let amount: Double

    var body: some View {
        HStack {
            Image(systemName: isEnabled ? "bolt.fill" : "bolt.slash")
                .foregroundColor(isEnabled ? .yellow : .gray)

            VStack(alignment: .leading, spacing: 2) {
                Text("Extra Usage")
                    .font(.subheadline)

                if isEnabled && amount > 0 {
                    Text("$\(String(format: "%.2f", amount))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(isEnabled ? "Enabled" : "Not enabled")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isEnabled ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isEnabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Action Buttons

struct ActionButtonsView: View {
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onRefresh) {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                    Text("Refresh")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.3), Color.blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Button(action: onQuit) {
                HStack {
                    Image(systemName: "power.circle.fill")
                        .font(.title3)
                    Text("Quit")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.red.opacity(0.3), Color.orange.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Status Footer

struct StatusFooterView: View {
    let lastUpdated: String?
    let status: ConnectionStatus
    @State private var memoryUsage: Double = 0
    @State private var peakMemory: Double = 0
    @State private var memoryHistory: [Double] = []
    private let memoryTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let maxHistoryPoints = 60  // 2 minutes of history at 2-second intervals

    var statusText: String {
        switch status {
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Error"
        case .noAuth: return "No credentials"
        case .authError: return "Auth failed"
        case .tokenExpired: return "Token expired"
        case .apiError: return "API error"
        }
    }

    var statusColor: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Connection status row
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let updated = lastUpdated {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("Updated \(updated)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Memory graph
            MemoryGraphView(
                history: memoryHistory,
                currentMemory: memoryUsage,
                peakMemory: peakMemory
            )
        }
        .padding(.top, 8)
        .onAppear { updateMemory() }
        .onReceive(memoryTimer) { _ in updateMemory() }
    }

    private func updateMemory() {
        let current = getMemoryUsageMB()
        memoryUsage = current
        if current > peakMemory {
            peakMemory = current
        }
        memoryHistory.append(current)
        if memoryHistory.count > maxHistoryPoints {
            memoryHistory.removeFirst()
        }
    }
}

// MARK: - Memory Graph View

struct MemoryGraphView: View {
    let history: [Double]
    let currentMemory: Double
    let peakMemory: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with current and peak
            HStack {
                Image(systemName: "memorychip")
                    .font(.caption)
                    .foregroundColor(.cyan)

                Text("Memory")
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Text(String(format: "%.1f MB", currentMemory))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("•")
                    .foregroundColor(.secondary)
                    .font(.caption2)

                Text(String(format: "Peak: %.1f MB", peakMemory))
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            // Graph
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    // Background grid lines
                    VStack(spacing: 0) {
                        ForEach(0..<4) { _ in
                            Divider()
                                .background(Color.gray.opacity(0.2))
                            Spacer()
                        }
                        Divider()
                            .background(Color.gray.opacity(0.2))
                    }

                    // Graph line
                    if history.count > 1 {
                        MemoryLineGraph(
                            data: history,
                            size: geo.size
                        )
                    }

                    // Current value indicator (right edge)
                    if !history.isEmpty {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 6, height: 6)
                            .shadow(color: .cyan.opacity(0.5), radius: 3)
                            .position(
                                x: geo.size.width - 3,
                                y: yPosition(for: history.last ?? 0, in: geo.size.height)
                            )
                    }
                }
            }
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Time labels
            HStack {
                Text("2m ago")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                Text("now")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private func yPosition(for value: Double, in height: CGFloat) -> CGFloat {
        guard !history.isEmpty else { return height }
        let minVal = (history.min() ?? 0) * 0.95
        let maxVal = max((history.max() ?? 100) * 1.05, minVal + 10)
        let normalized = (value - minVal) / (maxVal - minVal)
        return height - (CGFloat(normalized) * height)
    }
}

struct MemoryLineGraph: View {
    let data: [Double]
    let size: CGSize

    var body: some View {
        Path { path in
            guard data.count > 1 else { return }

            let minVal = (data.min() ?? 0) * 0.95
            let maxVal = max((data.max() ?? 100) * 1.05, minVal + 10)
            let range = maxVal - minVal

            let stepX = size.width / CGFloat(data.count - 1)

            for (index, value) in data.enumerated() {
                let x = CGFloat(index) * stepX
                let normalizedY = (value - minVal) / range
                let y = size.height - (CGFloat(normalizedY) * size.height)

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(
            LinearGradient(
                colors: [.cyan, .blue, .purple],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        // Fill under the line
        Path { path in
            guard data.count > 1 else { return }

            let minVal = (data.min() ?? 0) * 0.95
            let maxVal = max((data.max() ?? 100) * 1.05, minVal + 10)
            let range = maxVal - minVal

            let stepX = size.width / CGFloat(data.count - 1)

            path.move(to: CGPoint(x: 0, y: size.height))

            for (index, value) in data.enumerated() {
                let x = CGFloat(index) * stepX
                let normalizedY = (value - minVal) / range
                let y = size.height - (CGFloat(normalizedY) * size.height)
                path.addLine(to: CGPoint(x: x, y: y))
            }

            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [.cyan.opacity(0.3), .blue.opacity(0.1), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// Get current memory usage in MB
func getMemoryUsageMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    if result == KERN_SUCCESS {
        return Double(info.resident_size) / 1024.0 / 1024.0
    }
    return 0
}

// MARK: - Helper Functions

func loadClaudeColoredIcon() -> NSImage? {
    if let bundlePath = Bundle.main.resourcePath,
       let image = NSImage(contentsOfFile: bundlePath + "/claude-icon@2x.png") {
        image.size = NSSize(width: 24, height: 24)
        // NOT a template - keep original colors
        return image
    }
    return nil
}

