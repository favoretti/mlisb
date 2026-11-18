// Draws the app icon and writes every size the asset catalog needs.
// Run from the repo root: swift app/Icon/make-icon.swift
import AppKit
import SwiftUI

extension Color {
    init(_ hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Raw markdown on the left, the same thing as it should look on the right.
struct Icon: View {
    let ink = Color(0x1E1B2E)

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 186, style: .continuous)
        ZStack {
            tile.fill(LinearGradient(colors: [Color(0xFDFAF3), Color(0xE9E0CF)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
            ZStack {
                HStack(spacing: 0) { Rectangle().fill(ink); Color.clear }
                Text("#")
                    .font(.system(size: 340, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(0xB9B4D0))
                    .position(x: 206, y: 400)
                VStack(alignment: .leading, spacing: 38) {
                    RoundedRectangle(cornerRadius: 20).fill(ink).frame(width: 250, height: 74)
                    ForEach([290, 290, 190], id: \.self) { width in
                        RoundedRectangle(cornerRadius: 12).fill(ink.opacity(0.45)).frame(width: CGFloat(width), height: 30)
                    }
                }
                .position(x: 618, y: 412)
            }
            .clipShape(tile)
            tile.strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .black.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
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
