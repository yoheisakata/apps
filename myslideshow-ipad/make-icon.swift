#!/usr/bin/env swift
// 白背景+単色シルエットという自作アプリ共通の意匠([[app-icon-style]])はmyslideshow(Mac版)の
// make-icon.swiftから踏襲 ― モチーフ(山+太陽の「写真」プレート)も同じにして、Mac版・iPad版が
// 同じアプリの兄弟だと分かるようにした。**色だけ赤からmytube-ipadと同じ青(`#1B5E9E`)に
// 変更**して、iPad版であることを実機・ホーム画面上でも見分けやすくする(mytube-ipadで
// 確立した「iPad版は青、Mac版は赤」という区別の踏襲)。
// iOS向けのApp Icon(1024x1024、単一サイズ、アルファ無し ― iOSのApp Iconはアルファ
// チャンネルを持てない)を生成する。Xcodeの「1024だけ用意すればよい」App Icon方式を使うため、
// iconset/iconutilは不要(mytube-ipadと同じ方式)。
//   実行: swift make-icon.swift
//   → Sources/MySlideshowPad/Assets.xcassets/AppIcon.appiconset/icon-1024.png を出力
import AppKit

let bgWhite = NSColor.white
let silhouetteBlue = NSColor(srgbRed: 0x1B / 255, green: 0x5E / 255, blue: 0x9E / 255, alpha: 1) // #1B5E9E

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
    // iOSのApp Iconはシステム側で自動的に角丸マスクをかけるため、Mac版と違いここでは
    // 角丸にせず正方形いっぱいに背景を塗る(mytube-ipadのmake-icon.swiftと同じ注記)。
    bgWhite.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s)).fill()

    let inset = s * 0.08
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)

    // 中央に青い角丸長方形(写真のプレート、Mac版と同じ形)。中に山+太陽のシルエットを
    // 背景色(白)でくり抜く。
    let plateW = rect.width * 0.64
    let plateH = rect.height * 0.64
    let plateRect = NSRect(x: rect.midX - plateW / 2, y: rect.midY - plateH / 2, width: plateW, height: plateH)
    let plateRadius = plateW * 0.12
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: plateRadius, yRadius: plateRadius)

    // 太陽(円)
    let sunRadius = plateW * 0.13
    let sunCenter = NSPoint(x: plateRect.minX + plateW * 0.28, y: plateRect.maxY - plateH * 0.26)
    let sun = NSBezierPath(ovalIn: NSRect(
        x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2))

    // 山並み(2つの山を重ねた形)
    let mountains = NSBezierPath()
    let baseY = plateRect.minY + plateH * 0.16
    mountains.move(to: NSPoint(x: plateRect.minX + plateW * 0.04, y: baseY))
    mountains.line(to: NSPoint(x: plateRect.minX + plateW * 0.40, y: baseY + plateH * 0.46))
    mountains.line(to: NSPoint(x: plateRect.minX + plateW * 0.58, y: baseY + plateH * 0.24))
    mountains.line(to: NSPoint(x: plateRect.minX + plateW * 0.80, y: baseY + plateH * 0.52))
    mountains.line(to: NSPoint(x: plateRect.minX + plateW * 0.96, y: baseY))
    mountains.close()

    plate.append(sun)
    plate.append(mountains)
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
let appiconsetDir = "Sources/MySlideshowPad/Assets.xcassets/AppIcon.appiconset"
try! fm.createDirectory(atPath: appiconsetDir, withIntermediateDirectories: true)
savePNG(renderIcon(pixels: 1024), to: "\(appiconsetDir)/icon-1024.png")
print("✅ \(appiconsetDir)/icon-1024.png を生成しました")
