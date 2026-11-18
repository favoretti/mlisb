#if canImport(Sparkle)
import Combine
import Sparkle
import SwiftUI

/// Sparkle, started only when the bundle carries a feed URL and a signing key.
@MainActor
final class UpdaterModel: ObservableObject {
    private let controller: SPUStandardUpdaterController?
    private var subscriptions: Set<AnyCancellable> = []

    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyDownloads = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?

    nonisolated static func isConfigured(info: [String: Any]) -> Bool {
        ["SUFeedURL", "SUPublicEDKey"].allSatisfy {
            (info[$0] as? String)?.trimmingCharacters(in: .whitespaces).isEmpty == false
        }
    }

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        guard Self.isConfigured(info: info) else { controller = nil; return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.automaticallyChecksForUpdates).sink { [weak self] in self?.automaticallyChecks = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.automaticallyDownloadsUpdates).sink { [weak self] in self?.automaticallyDownloads = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.allowsAutomaticUpdates).sink { [weak self] in self?.allowsAutomaticUpdates = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.canCheckForUpdates).sink { [weak self] in self?.canCheck = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.lastUpdateCheckDate).sink { [weak self] in self?.lastCheck = $0 }.store(in: &subscriptions)
    }

    var isConfigured: Bool { controller != nil }

    func setAutomaticallyChecks(_ on: Bool) { controller?.updater.automaticallyChecksForUpdates = on }
    func setAutomaticallyDownloads(_ on: Bool) { controller?.updater.automaticallyDownloadsUpdates = on }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterModel

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheck)
    }
}
#endif
