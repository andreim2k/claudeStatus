import SwiftUI

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

    var body: some View {
        ZStack {
            // Liquid glass background
            LiquidGlassBackground()

            VStack(spacing: 0) {
                // Header with model indicator
                HeaderView(currentModel: activeModelName)

                ScrollView {
                    VStack(spacing: 16) {
                        // Usage cards (show remaining %)
                        UsageCardView(
                            title: "Current 5h Session",
                            subtitle: "",
                            percentage: 100 - usageData.session.used,
                            resetTime: usageData.session.resetTime,
                            gradient: Gradient(colors: [.cyan, .blue])
                        )

                        UsageCardView(
                            title: "Current Week (all models)",
                            subtitle: "",
                            percentage: 100 - usageData.weekAll.used,
                            resetTime: usageData.weekAll.resetTime,
                            gradient: Gradient(colors: [.purple, .pink])
                        )

                        UsageCardView(
                            title: "Current Week (Sonnet)",
                            subtitle: "",
                            percentage: 100 - usageData.weekSonnet.used,
                            resetTime: usageData.weekSonnet.resetTime,
                            gradient: Gradient(colors: [.orange, .red])
                        )

                        // Extra usage badge
                        ExtraUsageBadge(isEnabled: usageData.extraUsage)

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
                        onRefresh: { appDelegate.manualRefresh() },
                        onQuit: { NSApp.terminate(nil) }
                    )
                    .padding(12)
                }
                .background(.ultraThinMaterial)
            }
        }
        .frame(width: 320, height: 650)
    }
}

// MARK: - Liquid Glass Background

struct LiquidGlassBackground: View {
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

            // Animated blobs for liquid effect
            GeometryReader { geo in
                ZStack {
                    LiquidBlob(color: .cyan.opacity(0.15), size: 150)
                        .offset(x: -50, y: -30)

                    LiquidBlob(color: .purple.opacity(0.12), size: 180)
                        .offset(x: geo.size.width - 80, y: 100)

                    LiquidBlob(color: .pink.opacity(0.1), size: 120)
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
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 40)
            .scaleEffect(animate ? 1.1 : 0.9)
            .animation(
                .easeInOut(duration: 4)
                .repeatForever(autoreverses: true),
                value: animate
            )
            .onAppear { animate = true }
    }
}

// MARK: - Header

struct HeaderView: View {
    let currentModel: String

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

    var body: some View {
        HStack {
            Image(systemName: isEnabled ? "bolt.fill" : "bolt.slash")
                .foregroundColor(isEnabled ? .yellow : .gray)

            Text("Extra Usage")
                .font(.subheadline)

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
        .padding(.top, 8)
    }
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

