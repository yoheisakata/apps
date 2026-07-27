#!/usr/bin/env swift
// 薄い青グラデーション背景に、将棋駒・チェスナイト・碁石(黒白)を描いたアプリアイコンを生成する。
//   実行: swift make-icon.swift   →  Resources/AppIcon.png (2048x2048) を出力
// build.sh の build_icns() がこのマスター PNG から iconset/icns を都度生成するので、
// ここでは iconset/icns は作らない。
import AppKit

let blueTop = NSColor(srgbRed: 0.56, green: 0.78, blue: 0.95, alpha: 1)    // #8FC7F2
let blueBottom = NSColor(srgbRed: 0.31, green: 0.56, blue: 0.78, alpha: 1) // #4F8FC7

let cream = NSColor(srgbRed: 0.976, green: 0.941, blue: 0.847, alpha: 1) // #F9F0D8
let brown = NSColor(srgbRed: 0.42, green: 0.26, blue: 0.15, alpha: 1)    // 駒の縁
let white = NSColor.white
let black = NSColor.black
let stoneStroke = NSColor(srgbRed: 0.22, green: 0.40, blue: 0.56, alpha: 1)

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

    // 将棋駒(左上): 五角形(先細り、末広がり)
    let cx1 = s * 0.283
    let yTop = s * 0.84
    let yShoulder = s * 0.74
    let yBottom = s * 0.50
    let halfBottomW = s * 0.142
    let halfShoulderW = s * 0.105

    let koma = NSBezierPath()
    koma.move(to: NSPoint(x: cx1, y: yTop))
    koma.line(to: NSPoint(x: cx1 + halfShoulderW, y: yShoulder))
    koma.line(to: NSPoint(x: cx1 + halfBottomW, y: yBottom))
    koma.line(to: NSPoint(x: cx1 - halfBottomW, y: yBottom))
    koma.line(to: NSPoint(x: cx1 - halfShoulderW, y: yShoulder))
    koma.close()
    cream.setFill()
    koma.fill()
    brown.setStroke()
    koma.lineWidth = s * 0.012
    koma.stroke()

    let kanji = "王"
    let kanjiFont = NSFont(name: "HiraginoSans-W6", size: s * 0.2) ?? NSFont.boldSystemFont(ofSize: s * 0.2)
    let kanjiAttrs: [NSAttributedString.Key: Any] = [.font: kanjiFont, .foregroundColor: black]
    let kanjiStr = NSAttributedString(string: kanji, attributes: kanjiAttrs)
    let kanjiSize = kanjiStr.size()
    kanjiStr.draw(at: NSPoint(x: cx1 - kanjiSize.width / 2, y: (yBottom + yShoulder) / 2 - kanjiSize.height / 2))

    // チェスナイト(右上)
    let cx2 = s * 0.645
    let cy2 = s * 0.675
    let knightText = "♞"
    let knightFont = NSFont.systemFont(ofSize: s * 0.5)
    let knightAttrs: [NSAttributedString.Key: Any] = [.font: knightFont]
    let knightStr = NSAttributedString(string: knightText, attributes: knightAttrs)
    let knightSize = knightStr.size()
    let knightOrigin = NSPoint(x: cx2 - knightSize.width / 2, y: cy2 - knightSize.height / 2)

    g.saveGState()
    g.beginTransparencyLayer(auxiliaryInfo: nil)
    knightStr.draw(at: knightOrigin)
    g.setBlendMode(.sourceIn)
    g.setFillColor(white.cgColor)
    g.fill(CGRect(x: 0, y: 0, width: s, height: s))
    g.endTransparencyLayer()
    g.restoreGState()

    // 碁石(下段): 黒石・白石
    let stoneR = s * 0.13
    let stoneY = s * 0.254
    let blackCx = s * 0.341
    let whiteCx = s * 0.634

    let blackStone = NSBezierPath(ovalIn: NSRect(x: blackCx - stoneR, y: stoneY - stoneR, width: stoneR * 2, height: stoneR * 2))
    black.setFill()
    blackStone.fill()
    stoneStroke.setStroke()
    blackStone.lineWidth = s * 0.004
    blackStone.stroke()

    let whiteStone = NSBezierPath(ovalIn: NSRect(x: whiteCx - stoneR, y: stoneY - stoneR, width: stoneR * 2, height: stoneR * 2))
    white.setFill()
    whiteStone.fill()
    stoneStroke.setStroke()
    whiteStone.lineWidth = s * 0.004
    whiteStone.stroke()

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
