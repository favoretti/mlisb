// Draws the app icon and writes every size the asset catalog needs.
// Run from the repo root: swift app/Icon/make-icon.swift
import AppKit
import SwiftUI

extension Color {
    init(_ hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// "M↓" with the M drawn as a small node-and-edge diagram: markdown plus diagrams.
struct Glyph: View {
    let ink = Color(0x1E1B2E)
    let accent = Color(0xE4572E)
    // Vertices of the M inside the 824pt tile.
    let m: [CGPoint] = [.init(x: 170, y: 548), .init(x: 170, y: 276), .init(x: 305, y: 426), .init(x: 440, y: 276), .init(x: 440, y: 548)]

    var body: some View {
        ZStack {
            Path { $0.addLines(m) }
                .stroke(ink, style: StrokeStyle(lineWidth: 34, lineCap: .round, lineJoin: .round))
            ForEach(m.indices, id: \.self) { i in
                Circle().fill(ink).frame(width: 84, height: 84).position(m[i])
            }
            // Down arrow: shaft and head.
            Path { p in
                p.move(to: .init(x: 632, y: 276))
                p.addLine(to: .init(x: 632, y: 470))
            }
            .stroke(accent, style: StrokeStyle(lineWidth: 54, lineCap: .round))
            Path { p in
                p.move(to: .init(x: 556, y: 446))
                p.addLine(to: .init(x: 632, y: 548))
                p.addLine(to: .init(x: 708, y: 446))
            }
            .stroke(accent, style: StrokeStyle(lineWidth: 54, lineCap: .round, lineJoin: .round))
        }
    }
}

struct Icon: View {
    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 186, style: .continuous)
        ZStack {
            tile.fill(LinearGradient(colors: [Color(0xFDFAF3), Color(0xE9E0CF)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
            tile.strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .black.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
            Glyph().offset(x: -20).scaleEffect(1.1)
        }
        .frame(width: 824, height: 824)
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func png(_ pixels: Int) -> Data {
    let renderer = ImageRenderer(content: Icon().scaleEffect(CGFloat(pixels) / 1024).frame(width: CGFloat(pixels), height: CGFloat(pixels)))
    renderer.scale = 1
    let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: "app/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var images: [[String: String]] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try MainActor.assumeIsolated { png(points * scale) }.write(to: out.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("Contents.json"))
try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: out.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("wrote \(images.count) images to \(out.path)")
