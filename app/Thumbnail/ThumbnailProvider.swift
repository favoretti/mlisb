import AppKit
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let size = ThumbnailPage.size(fitting: request.maximumSize)
        let handle = try? FileHandle(forReadingFrom: request.fileURL)
        defer { try? handle?.close() }
        let head = (try? handle?.read(upToCount: ThumbnailText.maxBytes)) ?? nil
        // A cut in the middle of a character is trimmed; anything else not UTF-8 is blank.
        let text = head.flatMap { data in (0...3).lazy.compactMap { String(data: data.dropLast($0), encoding: .utf8) }.first } ?? ""
        let selection = ThumbnailText.select(from: text)
        let pixels = size.width * request.scale
        handler(QLThumbnailReply(contextSize: size) {
            ThumbnailPage.draw(selection, in: size, textVisible: pixels >= 64)
            return true
        }, nil)
    }
}

enum ThumbnailPage {
    static let design = NSSize(width: 240, height: 340)  // about 1:1.414, a sheet of paper

    static func size(fitting box: CGSize) -> NSSize {
        let scale = min(box.width / design.width, box.height / design.height)
        return NSSize(width: (design.width * scale).rounded(), height: (design.height * scale).rounded())
    }

    /// Fixed colours: thumbnails are cached, so they must not depend on the appearance.
    static func draw(_ selection: (title: String?, body: [String]), in size: NSSize, textVisible: Bool) {
        let transform = NSAffineTransform()
        transform.scale(by: size.width / design.width)
        transform.concat()
        let page = NSRect(origin: .zero, size: design)
        NSColor(srgbRed: 0.98, green: 0.97, blue: 0.94, alpha: 1).setFill()
        page.fill()
        NSBezierPath(rect: page).addClip()

        let margin: CGFloat = 20
        let column = NSRect(x: margin, y: margin, width: design.width - 2 * margin, height: design.height - 2 * margin)
        guard let title = selection.title else { return }
        if textVisible {
            let ink = NSColor(srgbRed: 0.15, green: 0.15, blue: 0.16, alpha: 1)
            let heading = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: ink])
            let titleHeight = ceil(heading.boundingRect(with: column.size, options: .usesLineFragmentOrigin).height)
            heading.draw(with: NSRect(x: column.minX, y: column.maxY - titleHeight, width: column.width, height: titleHeight), options: .usesLineFragmentOrigin)
            let body = NSAttributedString(string: selection.body.joined(separator: "\n"), attributes: [
                .font: NSFont.systemFont(ofSize: 9), .foregroundColor: ink.withAlphaComponent(0.8),
            ])
            body.draw(with: NSRect(x: column.minX, y: column.minY, width: column.width, height: column.height - titleHeight - 12), options: .usesLineFragmentOrigin)
        } else {
            NSColor(white: 0.55, alpha: 1).setFill()
            NSRect(x: column.minX, y: column.maxY - 18, width: column.width * 0.7, height: 14).fill()
            NSColor(white: 0.8, alpha: 1).setFill()
            for row in 0..<min(selection.body.count, 12) {
                NSRect(x: column.minX, y: column.maxY - 44 - CGFloat(row) * 16, width: column.width * (row % 3 == 2 ? 0.6 : 1), height: 8).fill()
            }
        }
    }
}
