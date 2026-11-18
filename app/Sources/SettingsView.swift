import SwiftUI

struct SettingsView: View {
#if canImport(Sparkle)
    @ObservedObject var updater: UpdaterModel
#endif
    @AppStorage("textSize") private var textSize = ReadingSettings.defaultSize
    @AppStorage("lineWidth") private var lineWidth = LineWidth.medium

    var body: some View {
        Form {
            Section("Reading") {
                LabeledContent("Text size") {
                    Stepper("\(ReadingSettings.clamp(textSize)) pt",
                            value: Binding(get: { ReadingSettings.clamp(textSize) }, set: { textSize = ReadingSettings.clamp($0) }),
                            in: ReadingSettings.sizes)
                }
                Picker("Line width", selection: $lineWidth) {
                    ForEach(LineWidth.allCases) { Text($0.label).tag($0) }
                }
            }
#if canImport(Sparkle)
            UpdatesSettings(updater: updater)
#endif
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if canImport(Sparkle)
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
