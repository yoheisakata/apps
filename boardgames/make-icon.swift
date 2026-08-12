#!/usr/bin/env swift
// 白背景に、濃い赤(任天堂レッド)のサイコロ(5の目)を描いたアプリアイコンを生成する。
//   実行: swift make-icon.swift   →  Resources/AppIcon.png (2048x2048) を出力
// build.sh の build_icns() がこのマスター PNG から iconset/icns を都度生成するので、
// ここでは iconset/icns は作らない。
import AppKit

let bgWhite = NSColor.white
let nintendoRed = NSColor(srgbRed: 0.902, green: 0.0, blue: 0.071, alpha: 1) // #E60012

let die = nintendoRed
let pipWhite = bgWhite   // 目の色(背景の白と揃える。赤いサイコロに白い目を「打ち抜く」)
let dieShadow = NSColor(white: 0, alpha: 0.18)

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext

    let s = CGFloat(pixels)
    let inset = s * 0.08
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [blueTop, blueBottom])!
    gradient.draw(in: bgPath, angle: -90)

    // サイコロ(白、5の目)を中央に正面向きで配置
    let dieSide = s * 0.56
    let dieRadius = dieSide * 0.18
    let dieRect = NSRect(x: -dieSide / 2, y: -dieSide / 2, width: dieSide, height: dieSide)
    let diePath = NSBezierPath(roundedRect: dieRect, xRadius: dieRadius, yRadius: dieRadius)

    g.saveGState()
    g.translateBy(x: s / 2, y: s / 2)

    // 落ち影
    g.saveGState()
    g.translateBy(x: s * 0.012, y: -s * 0.012)
    dieShadow.setFill()
    diePath.fill()
    g.restoreGState()

    white.setFill()
    diePath.fill()

    // 目(5の目): 四隅+中央
    let pipR = dieSide * 0.09
    let pipOffset = dieSide * 0.245
    let pipCenters = [
        NSPoint(x: -pipOffset, y: pipOffset), NSPoint(x: pipOffset, y: pipOffset),
        NSPoint(x: 0, y: 0),
        NSPoint(x: -pipOffset, y: -pipOffset), NSPoint(x: pipOffset, y: -pipOffset),
    ]
    pipBlue.setFill()
    for c in pipCenters {
        let pip = NSBezierPath(ovalIn: NSRect(x: c.x - pipR, y: c.y - pipR, width: pipR * 2, height: pipR * 2))
        pip.fill()
    }
    g.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
try? fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
savePNG(renderIcon(pixels: 2048), to: "Resources/AppIcon.png")
print("✅ Resources/AppIcon.png を生成しました")
