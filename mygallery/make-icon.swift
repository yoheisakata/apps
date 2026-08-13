#!/usr/bin/env swift
// 白背景に濃い赤の写真フレーム(SF Symbol "photo")のシルエットを描いたマスターアイコンを
// 生成する。mygames と同じ「白背景 + 単色シルエット」構成で、シルエット色(黒みのある濃い赤)は
// mygames/mytube/mymusic と共通(自作アプリでファミリー感を揃えている)。build.sh が
// Resources/AppIcon.png から iconset/icns をビルド時に都度生成するので、
// ここでは 1024x1024 の master PNG のみを出力する。
//   実行: swift make-icon.swift   →  Resources/AppIcon.png を出力
import AppKit

let bgWhite = NSColor.white
let silhouetteRed = NSColor(srgbRed: 0.70, green: 0.0, blue: 0.06, alpha: 1) // 黒みを足した濃い赤 (mygames と共通)

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

    bgWhite.setFill()
    path.fill()

    // 中央に赤い写真(山と太陽の入った額縁)アイコン(SF Symbol "photo")のシルエット
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
    cg.setFillColor(silhouetteRed.cgColor)
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
