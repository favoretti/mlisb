import Foundation

public enum DiagramLanguage: String, Sendable { case mermaid, d2 }
public enum DiagramTheme: String, Sendable { case light, dark }

public struct RenderedDiagram: Sendable {
    public let svg: String
    public let pdf: Data
    public let size: CGSize
}

public struct RenderError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}
