import AppKit
import MarkdownEngine
import MlisbKit
import Observation

/// Feeds the engine's synchronous diagram hook from the async `RenderService`:
/// a miss returns nil and starts a render; `version` changes when results land.
@MainActor @Observable final class DiagramStore {
    static let shared = DiagramStore()

    private(set) var version = 0

    private struct Key: Hashable { let language: DiagramLanguage; let theme: DiagramTheme; let source: String }
    @ObservationIgnored private var images: [Key: NSImage] = [:]
    @ObservationIgnored private var pending: Set<Key> = []

    func image(language: String, source: String) -> NSImage? {
        guard let language = DiagramLanguage(rawValue: language.lowercased()) else { return nil }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = Key(language: language, theme: dark ? .dark : .light, source: source)
        if let image = images[key] { return image }
        guard pending.insert(key).inserted else { return nil }
        Task {
            let image: NSImage?
            do {
                image = NSImage(data: try await RenderService.shared.render(language, source: source, theme: key.theme).pdf)
            } catch {
                image = Self.errorImage("\(language.rawValue): \(error.localizedDescription)")
            }
            if images.count > 200 { images.removeAll() }
            images[key] = image
            pending.remove(key)
            // One restyle for a burst of renders, not one per diagram.
            if pending.isEmpty { version += 1 }
        }
        return nil
    }

    private static func errorImage(_ message: String) -> NSImage {
        let text = NSAttributedString(string: "⚠︎ " + message, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.systemRed,
        ])
        let bounds = text.boundingRect(with: NSSize(width: 640, height: 400), options: .usesLineFragmentOrigin)
        return NSImage(size: NSSize(width: ceil(bounds.width), height: ceil(bounds.height)), flipped: false) { rect in
            text.draw(with: rect, options: .usesLineFragmentOrigin)
            return true
        }
    }
}

struct Diagrams: DiagramRenderer {
    // The engine styles on the main thread only.
    func image(language: String, source: String) -> NSImage? {
        MainActor.assumeIsolated { DiagramStore.shared.image(language: language, source: source) }
    }

    func fingerprint() -> AnyHashable {
        MainActor.assumeIsolated { DiagramStore.shared.version }
    }
}
