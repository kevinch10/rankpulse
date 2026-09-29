import SwiftUI

/// Notification switches, plus privacy choices for ads where required.
struct NotificationSettingsView: View {
    @Environment(RankingStore.self) private var store
    @Environment(AdsManager.self) private var ads
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(NotificationKind.allCases) { kind in
                        Toggle(isOn: Binding(get: { store.favourites.isEnabled(kind) },
                                             set: { store.favourites.setEnabled(kind, $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                Text(kind.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(Theme.magenta)
                        .disabled(store.favourites.notificationsAllowed == false)
                    }
                } header: {
                    Text("For your favourite teams")
                } footer: {
                    if store.favourites.codes.isEmpty {
                        Text("Swipe left on a team in Rankings, or tap ★ on its page, to follow it.")
                    }
                }
                if store.favourites.isEnabled(.weeklyDigest) && !store.favourites.codes.isEmpty {
                    Section {
                        Button {
                            guard let data = store.data else { return }
                            Task { await store.favourites.sendDigestPreview(data) }
                        } label: {
                            Label("Send a preview of this week's digest", systemImage: "paperplane")
                        }
                    }
                }
                if store.favourites.notificationsAllowed == false {
                    Section {
                        Text("Notifications are turned off for this app, so these switches can't do anything yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Turn on notifications in Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    }
                }
                if ads.privacyOptionsRequired {
                    Section("Privacy") {
                        Button("Ad privacy choices") { Task { await ads.presentPrivacyOptions() } }
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
