#!/usr/bin/env swift
// macOS Photos.app のアイコン(6枚の花びらが放射状に並ぶレインボー配色の
// 花/風車モチーフ)に寄せたシルエットに変更(2026-09-08、ユーザー指示
// 「シルエットは Mac の Photo アプリみたいにしてほしい」)。それまでの単色
// カメラグリフ・6芒星バッジからの方針転換 ― このモチーフだけは単色ではなく、
// 花びらごとに異なる色相のレインボー配色にする(Photos.appの実物がそうであるため)。
// build.sh が Resources/AppIcon.png から iconset/icns をビルド時に都度生成するので、
// ここでは 1024x1024 の master PNG のみを出力する。
//   実行: swift make-icon.swift   →  Resources/AppIcon.png を出力
import AppKit

let bgWhite = NSColor.white
let petalSaturation: CGFloat = 0.75
let petalBrightness: CGFloat = 0.92
let petalHueOffset: CGFloat = 0.12 // 一番上の花びらが黄色寄りになるよう色相環を回転

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

    // 6 rounded petals radiating from the center, each a different hue —
    // built from a single symmetric petal path (two quadratic curves from a
    // small base offset near center out to a tip) rotated 60° apart.
    let g = ctx.cgContext
    let cx = s * 0.5
    let cy = s * 0.5
    let petalCount = 6
    let petalLength = outerRect.width * 0.293 // 300/1024 scaled to outerRect proportions
    let petalWidth = outerRect.width * 0.254 // 260/1024
    let baseInset = outerRect.width * 0.0195 // 20/1024

    for i in 0..<petalCount {
        let angle = CGFloat(i) * (2 * .pi / CGFloat(petalCount)) + .pi / 2
        let hue = (CGFloat(i) / CGFloat(petalCount) + petalHueOffset).truncatingRemainder(dividingBy: 1.0)
        let color = NSColor(calibratedHue: hue, saturation: petalSaturation, brightness: petalBrightness, alpha: 1)

        let petalPath = CGMutablePath()
        let base = CGPoint(x: baseInset, y: 0)
        let tip = CGPoint(x: petalLength, y: 0)
        petalPath.move(to: base)
        petalPath.addQuadCurve(to: tip, control: CGPoint(x: petalLength * 0.42, y: petalWidth / 2))
        petalPath.addQuadCurve(to: base, control: CGPoint(x: petalLength * 0.42, y: -petalWidth / 2))
        petalPath.closeSubpath()

        g.saveGState()
        g.translateBy(x: cx, y: cy)
        g.rotate(by: angle)
        g.setFillColor(color.cgColor)
        g.addPath(petalPath)
        g.fillPath()
        g.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

savePNG(renderIcon(pixels: 1024), to: "Resources/AppIcon.png")
print("✅ Resources/AppIcon.png を生成しました")
