#!/usr/bin/env swift
// 白背景+単色シルエットへ再度統一(2026-09-08、ユーザー指示: 前の多色シルエット
// (紫グラデ+白三角形→濃いプレート+虹色グラデーション三角形)は「かっこよくない」
// との評価で、「シルエットは一色にして、おしゃれなシルエットにして」と明示された)。
// モチーフは角丸の再生三角形のみ(コーラル、単色)にした ― 候補として提示した
// 「プレート+三角形」「円バッジ+三角形」より、この最もミニマルな案がユーザーに
// 選ばれた。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let bgWhite = NSColor.white
let silhouetteCoral = NSColor(calibratedRed: 0.93, green: 0.29, blue: 0.35, alpha: 1)

// Rounds each corner of a triangle by a fixed radius using CGPath's arc-to.
func roundedTrianglePath(p1: CGPoint, p2: CGPoint, p3: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: p1)
    path.addArc(tangent1End: p2, tangent2End: p3, radius: radius)
    path.addArc(tangent1End: p3, tangent2End: p1, radius: radius)
    path.addArc(tangent1End: p1, tangent2End: p2, radius: radius)
    path.closeSubpath()
    return path
}

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
    let outerRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let outerRadius = outerRect.width * 0.225
    let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: outerRadius, yRadius: outerRadius)

    bgWhite.setFill()
    outerPath.fill()

    // Just a single rounded-corner play triangle, no background plate/circle —
    // the most minimal of the candidates, chosen over a plate- or badge-backed
    // version.
    let g = ctx.cgContext
    let cx = s * 0.5
    let cy = s * 0.5
    let triW = s * 0.34
    let triH = s * 0.40
    let triCx = cx + triW * 0.12
    let p1 = CGPoint(x: triCx - triW / 2, y: cy + triH / 2)
    let p2 = CGPoint(x: triCx - triW / 2, y: cy - triH / 2)
    let p3 = CGPoint(x: triCx + triW / 2, y: cy)
    let path = roundedTrianglePath(p1: p1, p2: p2, p3: p3, radius: s * 0.028)

    g.setFillColor(silhouetteCoral.cgColor)
    g.addPath(path)
    g.fillPath()

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
