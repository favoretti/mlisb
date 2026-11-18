import CryptoKit
import Foundation

public enum HistoryError: Error, LocalizedError {
    case corruptBlob(String)
    public var errorDescription: String? {
        switch self {
        case .corruptBlob(let id): "Stored version \(id.prefix(8)) is missing or damaged."
        }
    }
}

// History is keyed by the file's standardized path, so a moved or renamed file starts a new history.
public struct HistoryStore: Sendable {
    public enum Origin: String, Codable, Sendable { case opened, saved, external }

    public struct Version: Codable, Identifiable, Equatable, Sendable {
        public let id: String
        public let date: Date
        public let byteCount: Int
        public let origin: Origin
    }

    private struct Index: Codable {
        var path: String
        var versions: [Version] = []  // newest first
        var baseline: String?         // blob id
    }

    private let directory: URL

    /// The app passes a folder inside Application Support.
    public init(directory: URL) { self.directory = directory }

    /// Records `text` as the newest version of `file`. Returns nil (and stores nothing) when it equals the newest version.
    @discardableResult
    public func record(_ text: String, for file: URL, origin: Origin, date: Date = Date()) throws -> Version? {
        var index = readIndex(file) ?? Index(path: file.standardizedFileURL.path)
        let id = try storeBlob(text)
        if index.versions.first?.id == id { return nil }
        let version = Version(id: id, date: date, byteCount: text.utf8.count, origin: origin)
        index.versions.insert(version, at: 0)
        try write(index, to: indexURL(file))
        return version
    }

    public func versions(for file: URL) -> [Version] { readIndex(file)?.versions ?? [] }

    public func text(of version: Version) throws -> String { try readBlob(version.id) }

    /// The reviewed baseline survives closing the file.
    public func setReviewedBaseline(_ text: String, for file: URL) throws {
        var index = readIndex(file) ?? Index(path: file.standardizedFileURL.path)
        index.baseline = try storeBlob(text)
        try write(index, to: indexURL(file))
    }

    public func reviewedBaseline(for file: URL) -> String? {
        readIndex(file)?.baseline.flatMap { try? readBlob($0) }
    }

    /// Retention: 30 days, 25 MB per file, 250 MB overall. Always keeps each file's newest version and baseline.
    public func prune(now: Date = Date()) throws {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory.appendingPathComponent("index"), includingPropertiesForKeys: nil)) ?? []
        var indexes: [(url: URL, index: Index)] = urls.compactMap { u in readIndex(at: u).map { (u, $0) } }
        func size(_ id: String) -> Int {
            (try? fm.attributesOfItem(atPath: blobURL(id).path)[.size] as? Int) ?? 0
        }
        func referenced() -> Set<String> {
            Set(indexes.flatMap { $0.index.versions.map(\.id) + [$0.index.baseline].compactMap { $0 } })
        }

        let cutoff = now.addingTimeInterval(-30 * 86400)
        for i in indexes.indices {
            let kept = indexes[i].index.versions.enumerated().filter { $0.offset == 0 || $0.element.date >= cutoff }
            indexes[i].index.versions = kept.map(\.element)
            while indexes[i].index.versions.count > 1,
                  indexes[i].index.versions.reduce(0, { $0 + size($1.id) }) >= 25 << 20 {
                indexes[i].index.versions.removeLast()
            }
        }
        while referenced().reduce(0, { $0 + size($1) }) >= 250 << 20 {
            let oldest = indexes.indices.flatMap { i in indexes[i].index.versions.indices.dropFirst().map { (i, $0) } }
                .min { indexes[$0.0].index.versions[$0.1].date < indexes[$1.0].index.versions[$1.1].date }
            guard let o = oldest else { break }
            indexes[o.0].index.versions.remove(at: o.1)
        }

        for (url, index) in indexes { try write(index, to: url) }
        let live = referenced()
        let blobs = (try? fm.contentsOfDirectory(at: directory.appendingPathComponent("blobs"), includingPropertiesForKeys: nil)) ?? []
        for b in blobs where !live.contains(b.lastPathComponent) { try fm.removeItem(at: b) }
    }

    // MARK: Storage

    private static func sha(_ d: Data) -> String {
        SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    private func indexURL(_ file: URL) -> URL {
        directory.appendingPathComponent("index/\(Self.sha(Data(file.standardizedFileURL.path.utf8))).json")
    }

    private func blobURL(_ id: String) -> URL { directory.appendingPathComponent("blobs/\(id)") }

    private func readIndex(_ file: URL) -> Index? { readIndex(at: indexURL(file)) }

    private func readIndex(at url: URL) -> Index? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Index.self, from: $0) }
    }

    private func write(_ index: Index, to url: URL) throws {
        try write(JSONEncoder().encode(index), to: url)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func storeBlob(_ text: String) throws -> String {
        let raw = Data(text.utf8), id = Self.sha(raw)
        if (try? readBlob(id)) == nil {
            try write(try (raw as NSData).compressed(using: .zlib) as Data, to: blobURL(id))
        }
        return id
    }

    private func readBlob(_ id: String) throws -> String {
        guard let packed = try? Data(contentsOf: blobURL(id)),
              let raw = try? (packed as NSData).decompressed(using: .zlib) as Data,
              Self.sha(raw) == id else { throw HistoryError.corruptBlob(id) }
        return String(decoding: raw, as: UTF8.self)  // String(data:encoding:) would drop a BOM
    }
}
