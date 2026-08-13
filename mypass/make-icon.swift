#!/usr/bin/env swift
// mynetworth と同じ紫グラデーション背景に鍵穴シルエットを描いたアイコンを生成する。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let purpleTop = NSColor(srgbRed: 0.55, green: 0.36, blue: 0.96, alpha: 1)
let purpleBottom = NSColor(srgbRed: 0.36, green: 0.20, blue: 0.70, alpha: 1)

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let s = CGFloat(pixels)
    let inset = s * 0.08
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [purpleTop, purpleBottom])!
    gradient.draw(in: path, angle: -90)

    // 鍵穴（keyhole）シルエット: 上部の円 + 下部の台形
    let cx = s / 2
    let cy = s / 2

    // 円部分（鍵穴の上）
    let circleRadius = s * 0.16
    let circleCenter = CGPoint(x: cx, y: cy + s * 0.06)

    // 台形部分（鍵穴の下）
    let trapTopWidth = s * 0.10
    let trapBottomWidth = s * 0.16
    let trapHeight = s * 0.22
    let trapTop = circleCenter.y - circleRadius * 0.3
    let trapBottom = trapTop - trapHeight

    let keyhole = CGMutablePath()
    // 円を描く
    keyhole.addEllipse(in: CGRect(
        x: circleCenter.x - circleRadius,
        y: circleCenter.y - circleRadius,
        width: circleRadius * 2,
        height: circleRadius * 2))
    // 台形を描く
    keyhole.move(to: CGPoint(x: cx - trapTopWidth, y: trapTop))
    keyhole.addLine(to: CGPoint(x: cx - trapBottomWidth, y: trapBottom))
    keyhole.addLine(to: CGPoint(x: cx + trapBottomWidth, y: trapBottom))
    keyhole.addLine(to: CGPoint(x: cx + trapTopWidth, y: trapTop))
    keyhole.closeSubpath()

    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    cg.addPath(keyhole)
    cg.fillPath(using: .winding)

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
