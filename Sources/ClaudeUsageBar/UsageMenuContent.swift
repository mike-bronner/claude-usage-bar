import ClaudeUsageBarCore
import SwiftUI

/// The status block inside the menu: every indicator the Claude UI shows, for the selected account.
struct UsageMenuContent: View {
    let model: UsageModel

    /// Dark enough to read as an alert on the menu's glass.
    private static let alert = Color(red: 0.72, green: 0.10, blue: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            accountPicker
            if let status = model.selectedStatus {
                header(status)
                if let snapshot = status.snapshot {
                    limits(snapshot)
                        .opacity(status.isIdle ? 0.5 : 1)
                    if let credits = snapshot.credits {
                        Divider()
                        creditsSection(credits)
                            .opacity(status.isIdle ? 0.5 : 1)
                    }
                } else if case .loading = status.condition {
                    ProgressView().controlSize(.small)
                }
            }
            footer
        }
        // Native items indent 30 pt for the state column and end 12 pt short of the edge; line up
        // with them.
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .frame(width: 330, alignment: .leading)
    }

    // MARK: Sections

    /// A button, not a menu item: a native item dismisses the menu, a click in here does not.
    private var footer: some View {
        HStack {
            if let refreshed = model.lastRefresh {
                Text("Updated \(refreshed, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") { Task { await model.refreshAll() } }
                .controlSize(.small)
        }
    }

    /// Buttons rather than menu items: a native item dismisses the menu when picked, a click
    /// inside a custom view does not.
    @ViewBuilder
    private var accountPicker: some View {
        if model.accounts.count > 1 {
            HStack(spacing: 2) {
                ForEach(model.accounts) { account in
                    let selected = account.id == model.selectedAccount?.id
                    Button { model.selectedID = account.id } label: {
                        Text(account.displayName)
                            .lineLimit(1)
                            .font(.caption.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(1.5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6.5))
        } else if let account = model.accounts.first {
            Text(account.displayName).font(.headline)
        } else {
            Text("No Claude Code accounts found in your home directory.")
                .foregroundStyle(.secondary)
        }
    }

    private func header(_ status: UsageModel.Status) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.selectedAccount?.emailAddress ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let plan = status.plan {
                    Text(plan)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            switch status.condition {
            case .idle(let since):
                notice("Idle since \(since, style: .time) · please open Claude Code to refresh", symbol: "pause.circle")
            case .rateLimited(let until):
                notice("Rate limited by Anthropic · retrying \(until, style: .time)", symbol: "clock")
            case .failed(let reason):
                notice(Text(reason), symbol: "exclamationmark.triangle")
            case .loading, .live:
                EmptyView()
            }
        }
        .font(.callout)
    }

    private func notice(_ text: Text, symbol: String) -> some View {
        Label { text } icon: { Image(systemName: symbol) }
            .font(.caption)
            .foregroundStyle(Self.alert)
    }

    private func notice(_ text: LocalizedStringKey, symbol: String) -> some View {
        notice(Text(text), symbol: symbol)
    }

    private func limits(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = snapshot.session {
                limitRow("Current session", session, resetStyle: .countdown)
            }
            if let weekly = snapshot.weeklyAll {
                limitRow("Weekly · all models", weekly, resetStyle: .absolute)
            }
            ForEach(snapshot.weeklyScoped) { scoped in
                limitRow("Weekly · \(scoped.modelName ?? "scoped")", scoped, resetStyle: .absolute)
            }
        }
    }

    private enum ResetStyle { case countdown, absolute }

    private func limitRow(_ title: String, _ limit: UsageLimit, resetStyle: ResetStyle) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(limit.percent.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(limit.isElevated ? Color.orange : Color.primary)
            }
            .font(.callout)
            UsageBar(percent: limit.percent, tint: limit.isElevated ? .orange : .accentColor)
            // No reset means no window has opened for this bucket yet.
            Text(limit.resetsAt.map { resetText($0, style: resetStyle) } ?? "Not started")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resetText(_ date: Date, style: ResetStyle) -> String {
        switch style {
        case .countdown: "Resets in \(ResetFormatter.countdown(to: date))"
        case .absolute: "Resets \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        }
    }

    private func creditsSection(_ credits: UsageCredits) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Usage credits").font(.callout)
                Spacer()
                if credits.enabled {
                    Text("\(Int(credits.percent.rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(credits.severity == "normal" || credits.severity == nil ? Color.primary : Color.orange)
                } else {
                    Text(credits.disabledReason.map { "off · \($0.replacingOccurrences(of: "_", with: " "))" } ?? "off")
                        .foregroundStyle(.secondary)
                }
            }
            if credits.enabled {
                UsageBar(percent: credits.percent)
                Text(creditsDetail(credits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func creditsDetail(_ credits: UsageCredits) -> String {
        var parts: [String] = []
        if let used = credits.used { parts.append("\(used.formatted) used") }
        if let limit = credits.limit { parts.append("of \(limit.formatted)") }
        if let balance = credits.balance { parts.append("· balance \(balance.formatted)") }
        if let autoReload = credits.autoReload { parts.append("· auto-reload \(autoReload ? "on" : "off")") }
        return parts.joined(separator: " ")
    }
}

/// A capsule fill proportional to `percent`. Unlike `ProgressView`, zero draws nothing — AppKit's
/// linear style paints a minimum knob even at 0, and ignores a clear tint.
private struct UsageBar: View {
    let percent: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if percent > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * min(percent, 100) / 100)
                }
            }
        }
        .frame(height: 6)
    }
}
