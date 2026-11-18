#if canImport(Sparkle)
import SwiftUI

struct SettingsView: View {
    @ObservedObject var updater: UpdaterModel

    var body: some View {
        Form {
            UpdatesSettings(updater: updater)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct UpdatesSettings: View {
    @ObservedObject var updater: UpdaterModel

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        Section("Updates") {
            Toggle("Automatically check for updates",
                   isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.setAutomaticallyChecks($0) }))
            Toggle("Automatically download and install updates",
                   isOn: Binding(get: { updater.automaticallyDownloads }, set: { updater.setAutomaticallyDownloads($0) }))
                .disabled(!updater.automaticallyChecks || !updater.allowsAutomaticUpdates)
            LabeledContent("Current version", value: version)
            LabeledContent("Last checked") {
                if let date = updater.lastCheck {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Never").foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheck)
            }
        }
    }
}
#endif
