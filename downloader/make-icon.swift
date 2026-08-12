#!/usr/bin/env swift
// 薄い青グラデーション背景に下矢印(ダウンロード)アイコンを描いた macOS アプリアイコンを生成する。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let greenTop = NSColor(srgbRed: 0.365, green: 0.663, blue: 0.878, alpha: 1) // #5DA9E0
let greenBottom = NSColor(srgbRed: 0.106, green: 0.369, blue: 0.620, alpha: 1) // #1B5E9E

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
    // macOS 風: 余白を取った角丸スクエア。
    let inset = s * 0.08
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [greenTop, greenBottom])!
    gradient.draw(in: path, angle: -90)

    // 中央に下矢印 + トレイ(ダウンロードアイコン)。
    let glyphW = s * 0.42
    let shaftW = glyphW * 0.30
    let headW = glyphW
    let headH = glyphW * 0.55
    let shaftH = glyphW * 0.55
    let cx = rect.midX
    let topY = rect.midY + (shaftH + headH) / 2 - shaftH * 0.15

    let shaftRect = NSRect(x: cx - shaftW / 2, y: topY - shaftH, width: shaftW, height: shaftH)
    NSColor.white.setFill()
    NSBezierPath(rect: shaftRect).fill()

    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: cx - headW / 2, y: topY - shaftH))
    tri.line(to: NSPoint(x: cx + headW / 2, y: topY - shaftH))
    tri.line(to: NSPoint(x: cx, y: topY - shaftH - headH))
    tri.close()
    tri.fill()

    let trayW = glyphW * 1.5
    let trayH = glyphW * 0.16
    let trayY = rect.midY - (shaftH + headH) / 2 - glyphW * 0.22
    let trayRect = NSRect(x: cx - trayW / 2, y: trayY, width: trayW, height: trayH)
    NSBezierPath(roundedRect: trayRect, xRadius: trayH / 2, yRadius: trayH / 2).fill()

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

// (論理サイズ, @2x か)
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

// iconutil で .icns に変換。
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset, "-o", "AppIcon.icns"]
try! proc.run()
proc.waitUntilExit()
print(proc.terminationStatus == 0 ? "✅ AppIcon.icns を生成しました" : "❌ iconutil 失敗")
