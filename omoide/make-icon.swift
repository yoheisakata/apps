#!/usr/bin/env swift
// 紫グラデーション背景にビデオカメラアイコンを描いたアプリアイコンを生成する。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let purpleTop = NSColor(srgbRed: 0.55, green: 0.36, blue: 0.96, alpha: 1)    // #8C5CF5
let purpleBottom = NSColor(srgbRed: 0.36, green: 0.20, blue: 0.70, alpha: 1) // #5C33B3

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

    // ビデオカメラアイコン（フィルムカメラ風）
    NSColor.white.setFill()

    let cx = s / 2
    let cy = s / 2

    // カメラ本体（角丸長方形）
    let bodyW = s * 0.36
    let bodyH = s * 0.26
    let bodyX = cx - bodyW / 2 - s * 0.04
    let bodyY = cy - bodyH / 2
    let bodyRect = CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: s * 0.03, yRadius: s * 0.03)
    bodyPath.fill()

    // 再生三角（カメラの右側）
    let triX = bodyX + bodyW + s * 0.02
    let triW = s * 0.14
    let triH = s * 0.18
    let triPath = NSBezierPath()
    triPath.move(to: NSPoint(x: triX, y: cy + triH / 2))
    triPath.line(to: NSPoint(x: triX + triW, y: cy))
    triPath.line(to: NSPoint(x: triX, y: cy - triH / 2))
    triPath.close()
    triPath.fill()

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
