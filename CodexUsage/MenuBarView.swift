import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var service: CodexUsageService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex Usage").font(.headline)

            if let primary = service.limits?.primary {
                LimitView(title: "5-hour limit", window: primary, resetText: relativeReset(primary.resetDate))
            }
            if let secondary = service.limits?.secondary {
                Divider()
                LimitView(title: "Weekly limit", window: secondary, resetText: absoluteReset(secondary.resetDate))
            }

            if service.limits == nil && service.isRefreshing {
                HStack { ProgressView().controlSize(.small); Text("Loading usage…") }
                    .foregroundStyle(.secondary)
            }
            if let error = service.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let updated = service.lastUpdated {
                Text("Last updated: \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            Button { service.refresh() } label: {
                Label(service.isRefreshing ? "Refreshing…" : "Refresh Now", systemImage: "arrow.clockwise")
            }.disabled(service.isRefreshing)

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in updateLaunchAtLogin(enabled) }
            ))

            Divider()
            Button("Quit CodexUsage") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { service.refresh() }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func relativeReset(_ date: Date?) -> String {
        guard let date else { return "Reset time unavailable" }
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        return "Resets in \(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    private func absoluteReset(_ date: Date?) -> String {
        guard let date else { return "Reset time unavailable" }
        return "Resets \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }
}

private struct LimitView: View {
    let title: String
    let window: RateLimitWindow
    let resetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).fontWeight(.medium)
            HStack {
                Text("\(window.remainingPercent)% remaining").font(.title3).fontWeight(.semibold)
                Spacer()
                Text(resetText).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(window.remainingPercent), total: 100)
                .tint(color)
        }
    }

    private var color: Color {
        switch window.remainingPercent {
        case 0..<10: .red
        case 10..<25: .orange
        default: .accentColor
        }
    }
}
