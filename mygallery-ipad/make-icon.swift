#!/usr/bin/env swift
// 白背景+単色シルエットという自作iPadアプリ共通の意匠([[app-icon-style]]、
// mytube-ipad/myslideshow-ipadのmake-icon.swiftで確立)を踏襲する。**モチーフは
// mygallery(Mac版)のmake-icon.swiftと同じ「SF Symbol 'photo'(山と太陽の入った
// 額縁アイコン)のシルエット」を維持する** ― Mac版は紫グラデーション背景+白
// シルエットだが、iPad版は他の2つのiPadアプリ(mytube-ipad/myslideshow-ipad)と
// 同じ「白背景+単色シルエット」の型に合わせ、背景をグラデーションではなく白の
// ベタ塗りにする。
//
// **色はMac版の紫(`0.55, 0.36, 0.96`)をそのまま使わない**(mytube-ipad/
// myslideshow-ipadが確立した「iPad版はMac版と別の色にして見分けやすくする」
// 慣例に従う)。mytube-ipad/myslideshow-ipadはどちらもすでに同じ青(`#1B5E9E`)を
// 使っているため、3本目のiPadアプリに同じ青を選ぶとホーム画面での見分けが
// つきにくくなる。ここでは寒色系でまとまりを保ちつつ別の色相になるティール
// (`#12766B`)を選んだ。
//   実行: swift make-icon.swift
//   → Sources/MyGalleryPad/Assets.xcassets/AppIcon.appiconset/icon-1024.png を出力
import AppKit

let bgWhite = NSColor.white
let silhouetteTeal = NSColor(srgbRed: 0x12 / 255, green: 0x76 / 255, blue: 0x6B / 255, alpha: 1) // #12766B

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    // iOSのApp Iconはアルファチャンネルを持てないが、NSGraphicsContextの安定動作の
    // ためにNSBitmapImageRep自体はhasAlpha:trueで作る(mytube-ipad/myslideshow-ipadの
    // make-icon.swiftと同じ構成)。全面を不透明色で塗りつぶすため実質アルファは常に255に
    // なり、savePNG側で明示的にアルファ無しのPNGへ変換する。
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

    // 中央にSF Symbol "photo"(山と太陽の入った額縁、mygallery Mac版と同じモチーフ)の
    // シルエットを描く。
    let glyphSize = s * 0.46
    let config = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        fatalError("SF Symbol 'photo' not found")
    }
    let symbolSize = symbol.size
    let origin = NSPoint(x: (s - symbolSize.width) / 2, y: (s - symbolSize.height) / 2)

    let cg = ctx.cgContext
    cg.saveGState()
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    cg.setBlendMode(.sourceIn)
    cg.setFillColor(silhouetteTeal.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: s, height: s))
    cg.endTransparencyLayer()
    cg.restoreGState()

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
let appiconsetDir = "Sources/MyGalleryPad/Assets.xcassets/AppIcon.appiconset"
try! fm.createDirectory(atPath: appiconsetDir, withIntermediateDirectories: true)
savePNG(renderIcon(pixels: 1024), to: "\(appiconsetDir)/icon-1024.png")
print("✅ \(appiconsetDir)/icon-1024.png を生成しました")
