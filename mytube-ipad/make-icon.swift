#!/usr/bin/env swift
// 白背景+単色シルエットという自作アプリ共通の意匠([[app-icon-style]])はmytube(Mac版)の
// make-icon.swiftから踏襲。**モチーフの変遷**: 当初はMac版と同じ「赤い横長の角丸プレート+
// 白い再生三角形」だったが、これがYouTubeのロゴと形が酷似しており「アイコンがyoutubeっぽ
// すぎる」という指摘を受け(2026-08-27)、いったん「縦長のタブレット本体+ホームボタン」
// というiPadらしいモチーフに変更した。しかしその後「形は戻して、シルエットは青にして」
// という要望を受け、**形はMac版と同じ横長プレート+三角形に戻し、色だけ赤から青
// (`#1B5E9E`、自作アプリが以前使っていた青系シルエットと同じ値)に変えて差別化する**方針に
// 変更した(2026-08-27)。iOS向けのApp Icon(1024x1024、単一サイズ、アルファ無し ― iOSの
// App Iconはアルファチャンネルを持てない)を生成する。Xcodeの新しい「1024だけ用意すれば
// よい」App Icon方式を使うため、iconset/iconutilは不要。
//   実行: swift make-icon.swift
//   → Sources/MyTubePad/Assets.xcassets/AppIcon.appiconset/icon-1024.png を出力
import AppKit

let bgWhite = NSColor.white
let silhouetteBlue = NSColor(srgbRed: 0x1B / 255, green: 0x5E / 255, blue: 0x9E / 255, alpha: 1) // #1B5E9E

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    // iOSのApp Iconはアルファチャンネルを持てないが、NSGraphicsContextの安定動作の
    // ためにNSBitmapImageRep自体はhasAlpha:trueで作る(mytube Mac版のmake-icon.swiftと
    // 同じ構成)。全面を不透明色で塗りつぶすため実質アルファは常に255になり、
    // savePNG側で明示的にアルファ無しのPNGへ変換する。
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let s = CGFloat(pixels)
    // iOSのApp Iconはシステム側で自動的に角丸マスクをかけるため、Mac版と違い
    // ここでは角丸にせず正方形いっぱいに背景を塗る(独自に角丸を描くと、システムの
    // マスクと二重になって内側にさらに小さい角丸が透けて見える)。
    bgWhite.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s)).fill()

    let inset = s * 0.08
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)

    // 中央に横長の角丸長方形(再生ボタンのプレート、mytube Mac版と同じ形)。
    // 中の三角形は背景色(白)でくり抜く。
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
    silhouetteBlue.setFill()
    plate.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// アルファチャンネルを持つ`rep`を、不透明(アルファ無し)なPNGとして書き出す。
// iOSのApp IconはXcode/App Store Connectがアルファ入りPNGを拒否するため必須の変換。
func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    let size = rep.pixelsWide
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
    let opaqueImage = ctx.makeImage()!
    let opaqueRep = NSBitmapImageRep(cgImage: opaqueImage)
    let data = opaqueRep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let appiconsetDir = "Sources/MyTubePad/Assets.xcassets/AppIcon.appiconset"
try! fm.createDirectory(atPath: appiconsetDir, withIntermediateDirectories: true)
savePNG(renderIcon(pixels: 1024), to: "\(appiconsetDir)/icon-1024.png")
print("✅ \(appiconsetDir)/icon-1024.png を生成しました")
