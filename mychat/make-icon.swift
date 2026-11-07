#!/usr/bin/env swift
// オレンジ〜コーラルのグラデーション背景に吹き出しシルエットを描いたアイコンを生成する。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let topColor = NSColor(srgbRed: 0.93, green: 0.55, blue: 0.36, alpha: 1)
let bottomColor = NSColor(srgbRed: 0.75, green: 0.33, blue: 0.22, alpha: 1)

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
    NSGradient(colors: [topColor, bottomColor])!
        .draw(in: NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), angle: -90)

    // 吹き出し: 角丸の本体 + 左下のしっぽ
    let bubble = CGRect(x: s * 0.22, y: s * 0.36, width: s * 0.56, height: s * 0.38)
    let path = CGMutablePath()
    path.addRoundedRect(in: bubble, cornerWidth: s * 0.12, cornerHeight: s * 0.12)
    path.move(to: CGPoint(x: s * 0.32, y: s * 0.38))
    path.addLine(to: CGPoint(x: s * 0.28, y: s * 0.24))
    path.addLine(to: CGPoint(x: s * 0.46, y: s * 0.37))
    path.closeSubpath()
    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    cg.addPath(path)
    cg.fillPath(using: .winding)

    // 吹き出しの中の「…」
    cg.setFillColor(CGColor(red: 0.80, green: 0.38, blue: 0.25, alpha: 1))
    let dot = s * 0.065
    for i in 0..<3 {
        let x = s * 0.5 + CGFloat(i - 1) * s * 0.13 - dot / 2
        cg.fillEllipse(in: CGRect(x: x, y: bubble.midY - dot / 2, width: dot, height: dot))
    }

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
    savePNG(renderIcon(pixels: pixels), to: "\(iconset)/icon_\(size)x\(size)\(suffix).png")
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset, "-o", "AppIcon.icns"]
try! proc.run()
proc.waitUntilExit()
print(proc.terminationStatus == 0 ? "✅ AppIcon.icns を生成しました" : "❌ iconutil 失敗")
