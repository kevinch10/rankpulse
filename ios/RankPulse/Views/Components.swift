import SwiftUI

struct FlagView: View {
    let code: String
    var width: CGFloat = 28

    var body: some View {
        AsyncImage(url: Config.flagURL(code)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.secondary.opacity(0.15)
        }
        .frame(width: width, height: width * 2 / 3)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}


struct RankMove: View {
    let change: Int

    var body: some View {
        if change == 0 {
            Text("–").foregroundStyle(.secondary)
        } else {
            HStack(spacing: 2) {
                Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .imageScale(.small)
                Text("\(abs(change))")
            }
            .foregroundStyle(change > 0 ? .green : .red)
            .accessibilityLabel(change > 0 ? "Up \(change)" : "Down \(-change)")
        }
    }
}

struct ConfedMenu: View {
    @Binding var selection: Confederation

    var body: some View {
        Menu {
            Picker("Confederation", selection: $selection) {
                ForEach(Confederation.allCases) { Text($0.menuTitle).tag($0) }
            }
        } label: {
            Label(selection == .all ? "Confederation" : selection.rawValue,
                  systemImage: selection == .all ? "globe" : "globe.europe.africa.fill")
        }
    }
}

struct MatchRow: View {
    let match: Match
    var fixture = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                side(match.home, match.homeName, match.homeDelta, leading: true)
                Group {
                    if fixture, let date = match.kickoffDate {
                        Text(date, format: .dateTime.hour().minute())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(match.scoreText).foregroundStyle(.white)
                    }
                }
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(fixture ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Theme.night), in: .rect(cornerRadius: 9))
                side(match.away, match.awayName, match.awayDelta, leading: false)
            }
            HStack(spacing: 6) {
                if match.isLive {
                    Text("LIVE").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Theme.magenta, in: .capsule)
                }
                Text([match.competition, match.stageText].compactMap { $0 }.joined(separator: " · "))
                if let i = match.importance {
                    Text("Weight \(i)").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(accent, in: .capsule)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 4).padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
    }

    @Environment(RankingStore.self) private var store
    private var accent: Color { Theme.confedColor(store.confed(of: match.home)) }

    private func side(_ code: String, _ name: String, _ delta: Double?, leading: Bool) -> some View {
        HStack(spacing: 6) {
            if leading { FlagView(code: code, width: 22) }
            VStack(alignment: leading ? .leading : .trailing, spacing: 1) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if let delta, match.isCounted {
                    Text(delta.signed).font(.caption2.monospaced()).foregroundStyle(delta.tone)
                }
            }
            if !leading { FlagView(code: code, width: 22) }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }
}

/// Where the numbers stand right now: updating, how fresh, or why not.
struct StatusBanner: View {
    @Environment(RankingStore.self) private var store

    var body: some View {
        Group {
            if store.isLoading {
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Updating…") }
            } else if let error = store.error {
                Label(error, systemImage: "wifi.slash")
            } else if store.isSnapshot {
                Label("Showing saved rankings — pull down to update", systemImage: "arrow.clockwise")
            } else if let updated = store.updatedAt {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                  VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text("Updated \(updated, format: .relative(presentation: .named))") +
                        Text(store.isStale ? " · may be out of date, pull down to refresh" : "")
                    } icon: {
                        Image(systemName: store.isStale ? "exclamationmark.triangle" : "checkmark.circle")
                    }
                    .foregroundStyle(store.isStale ? Theme.orange : .secondary)
                    if let live = store.liveCheckedAt {
                        Label {
                            Text("Live scores from FIFA · checked \(live, format: .relative(presentation: .named))")
                        } icon: {
                            Circle().fill(Theme.magenta).frame(width: 7, height: 7)
                        }
                    }
                  }
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Points each team would gain or lose for each result of an upcoming match,
/// laid out as a small Win / Draw / Loss table.
struct PredictionView: View {
    let match: Match
    var focus: String? = nil

    private static let outcomes: [(key: String, label: String)] = [
        ("win", "Win"), ("draw", "Draw"), ("pensWin", "Win on pens"), ("pensLoss", "Lose on pens"), ("loss", "Loss"),
    ]

    var body: some View {
        if let p = match.prediction {
            VStack(spacing: 6) {
                HStack {
                    Text("POINTS AT STAKE").font(.caption2.weight(.heavy)).tracking(0.6)
                    Spacer()
                    Text(caption).font(.caption2).foregroundStyle(.secondary)
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 4) {
                    GridRow {
                        Text(match.homeName).gridColumnAlignment(.leading).opacity(opacity(match.home))
                        Text("if they…").foregroundStyle(.secondary).gridColumnAlignment(.center)
                        Text(match.awayName).gridColumnAlignment(.trailing).opacity(opacity(match.away))
                    }
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    ForEach(Self.outcomes.filter { p.home[$0.key] != nil }, id: \.key) { o in
                        GridRow {
                            value(p.home[o.key]).opacity(opacity(match.home))
                            Text(o.label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            value(p.away[o.key]).opacity(opacity(match.away))
                        }
                    }
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .combine)
        }
    }

    private func opacity(_ code: String) -> Double { focus == nil || focus == code ? 1 : 0.45 }

    private func value(_ v: Double?) -> some View {
        let v = v ?? 0
        return Text(v.signed)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(v.tone)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(v.tone.opacity(0.12), in: .capsule)
            .fixedSize()
    }

    private var caption: String {
        var parts = match.importance.map { ["Match weight \($0)"] } ?? []
        if match.knockout == true { parts.append("knockout: loser keeps its points") }
        return parts.joined(separator: " · ")
    }
}

struct NotificationStatus: View {
    @Environment(RankingStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch store.favourites.notificationsAllowed {
        case true?:
            Label("You'll be notified when these teams gain or lose points or places.", systemImage: "bell.badge.fill")
        case false?:
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            } label: {
                Label("Notifications are off — tap to turn them on in Settings.", systemImage: "bell.slash")
            }
        case nil:
            EmptyView()
        }
    }
}
