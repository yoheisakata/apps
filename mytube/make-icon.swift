#!/usr/bin/env swift
// 薄い青の角丸スクエア(downloader/organizer/photo-galleryと共通)に白い再生ボタン(台形)を描き、
// 中央の三角形は背景色でくり抜いた macOS アプリアイコンを生成する。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let bgTop = NSColor(srgbRed: 0.365, green: 0.663, blue: 0.878, alpha: 1)    // #5DA9E0
let bgBottom = NSColor(srgbRed: 0.106, green: 0.369, blue: 0.620, alpha: 1) // #1B5E9E

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

    let gradient = NSGradient(colors: [bgTop, bgBottom])!
    gradient.draw(in: path, angle: -90)

    // 中央に白い角丸長方形(再生ボタンのプレート)。中の三角形は背景色でくり抜く。
    let plateW = rect.width * 0.62
    let plateH = rect.height * 0.44
    let plateRect = NSRect(x: rect.midX - plateW / 2, y: rect.midY - plateH / 2, width: plateW, height: plateH)
    let plateRadius = plateH * 0.28
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: plateRadius, yRadius: plateRadius)

    let triW = plateW * 0.34
    let triH = plateH * 0.5
    let cx = rect.midX + triW * 0.12
    let cy = rect.midY
    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: cx - triW / 2, y: cy + triH / 2))
    tri.line(to: NSPoint(x: cx - triW / 2, y: cy - triH / 2))
    tri.line(to: NSPoint(x: cx + triW / 2, y: cy))
    tri.close()

    plate.append(tri)
    plate.windingRule = .evenOdd
    NSColor.white.setFill()
    plate.fill()

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
