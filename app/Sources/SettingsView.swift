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
            SetupSettings()
#if canImport(Sparkle)
            UpdatesSettings(updater: updater)
#endif
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SetupSettings: View {
    @State private var isDefault = DefaultApp.isDefault
    @State private var tool = CommandLineTool.installedPath
    @State private var failed = false

    var body: some View {
        Section("Setup") {
            LabeledContent("Default app for Markdown files") {
                if isDefault {
                    Label("mlisb", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                } else {
                    Button("Make Default") {
                        Task {
                            do { try await DefaultApp.makeDefault() } catch { failed = true }
                            isDefault = DefaultApp.isDefault
                        }
                    }
                }
            }
            // Both can change outside the app (Finder, Terminal), so look again when we come back.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                isDefault = DefaultApp.isDefault
                tool = CommandLineTool.installedPath
            }
            .alert("mlisb could not make itself the default", isPresented: $failed) {
                Button("OK") {}
            } message: {
                Text("In Finder, select a Markdown file and choose File > Get Info. Under “Open with”, pick mlisb and click Change All.")
            }
            LabeledContent {
                if let tool {
                    Text(tool).foregroundStyle(.secondary).textSelection(.enabled)
                } else {
                    Button("Install…") { showInstallCommandLineTool() }
                }
            } label: {
                Text("Command line tool")
                Text("Opens files and folders from Terminal, for example “mlisb .”")
            }
            LabeledContent {
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("mlisb hook install", forType: .string)
                }
            } label: {
                Text("Claude Code")
                Text("Run “mlisb hook install” in Terminal, and every Markdown file the agent writes opens here.")
            }
        }
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
