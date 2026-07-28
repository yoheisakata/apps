#!/usr/bin/env swift
// 緑グラデーション背景（downloaderと共通）に白い🗂️（インデックスディバイダー、整理整頓のイメージ）の
// シルエットを描いたアプリアイコンを生成する。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let blueTop = NSColor(srgbRed: 0.17, green: 0.72, blue: 0.45, alpha: 1)    // #2BB673（downloaderと共通）
let blueBottom = NSColor(srgbRed: 0.11, green: 0.48, blue: 0.30, alpha: 1) // #1B7A4D（downloaderと共通）

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

    let gradient = NSGradient(colors: [blueTop, blueBottom])!
    gradient.draw(in: path, angle: -90)

    // 中央に白いインデックスディバイダー(🗂️)のシルエット
    let text = "🗂️"
    let fontSize = s * 0.5
    let font = NSFont.systemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let str = NSAttributedString(string: text, attributes: attrs)
    let textSize = str.size()
    let origin = NSPoint(x: (s - textSize.width) / 2, y: (s - textSize.height) / 2 - s * 0.01)

    let cg = ctx.cgContext
    cg.saveGState()
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    str.draw(at: origin)
    cg.setBlendMode(.sourceIn)
    cg.setFillColor(NSColor.white.cgColor)
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
