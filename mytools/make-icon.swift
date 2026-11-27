#!/usr/bin/env swift
// 白背景に単色（ダークスレート）の SF Symbol "wrench.and.screwdriver.fill"（レンチ＋ドライバー、
// ツールのイメージ）を描いたアプリアイコンを生成する。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let glyphColor = NSColor(srgbRed: 0.227, green: 0.267, blue: 0.314, alpha: 1) // #3A4450 ダークスレート

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let s = CGFloat(pixels)
    let inset = s * 0.08
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // 白背景
    NSColor.white.setFill()
    path.fill()

    // 中央にツールのシルエット（単色）
    let glyphSize = s * 0.56
    let config = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .medium)
    guard let symbol = NSImage(systemSymbolName: "wrench.and.screwdriver.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        fatalError("SF Symbol 'wrench.and.screwdriver.fill' not found")
    }
    let symbolSize = symbol.size
    let origin = NSPoint(x: (s - symbolSize.width) / 2, y: (s - symbolSize.height) / 2)

    let cg = ctx.cgContext
    cg.saveGState()
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    cg.setBlendMode(.sourceIn)
    cg.setFillColor(glyphColor.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: s, height: s))
    cg.endTransparencyLayer()
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let iconset = "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let specs: [(Int, Bool)] = [
    (16, false), (16, true),
    (32, false), (32, true),
    (128, false), (128, true),
    (256, false), (256, true),
    (512, false), (512, true),
]
for (size, retina) in specs {
    let pixels = retina ? size * 2 : size
    let suffix = retina ? "@2x" : ""
    let name = "\(iconset)/icon_\(size)x\(size)\(suffix).png"
    savePNG(renderIcon(pixels: pixels), to: name)
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset, "-o", "AppIcon.icns"]
try! proc.run()
proc.waitUntilExit()
print(proc.terminationStatus == 0 ? "✅ AppIcon.icns を生成しました" : "❌ iconutil 失敗")
