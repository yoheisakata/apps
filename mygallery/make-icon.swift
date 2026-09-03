#!/usr/bin/env swift
// MyPassと同じ紫グラデーション背景に、白の写真フレーム(SF Symbol "photo")の
// シルエットを描いたマスターアイコンを生成する。MyGalleryはMyTubeと同じく
// 2026-09-02に「白背景+黒シルエット」の統一から離脱し、MyPassと背景色を揃えた
// (ユーザー指示)。build.sh が Resources/AppIcon.png から iconset/icns を
// ビルド時に都度生成するので、ここでは 1024x1024 の master PNG のみを出力する。
//   実行: swift make-icon.swift   →  Resources/AppIcon.png を出力
import AppKit

let purpleTop = NSColor(srgbRed: 0.55, green: 0.36, blue: 0.96, alpha: 1) // MyPassと同じ紫グラデーション
let purpleBottom = NSColor(srgbRed: 0.36, green: 0.20, blue: 0.70, alpha: 1)
let silhouetteWhite = NSColor.white // 白 (旧・黒シルエットから変更)

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

    let gradient = NSGradient(colors: [purpleTop, purpleBottom])!
    gradient.draw(in: path, angle: -90)

    // 中央に白い写真(山と太陽の入った額縁)アイコン(SF Symbol "photo")のシルエット
    let glyphSize = s * 0.46
    let config = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        fatalError("SF Symbol 'photo' not found")
    }
    let symbolSize = symbol.size
    let origin = NSPoint(x: (s - symbolSize.width) / 2, y: (s - symbolSize.height) / 2)

    let cg = ctx.cgContext
    cg.saveGState()
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    cg.setBlendMode(.sourceIn)
    cg.setFillColor(silhouetteWhite.cgColor)
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

savePNG(renderIcon(pixels: 1024), to: "Resources/AppIcon.png")
print("✅ Resources/AppIcon.png を生成しました")
