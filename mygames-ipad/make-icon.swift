#!/usr/bin/env swift
// MyGames Pad(iPad版)のアイコン。ユーザー指示により、他のiPad版アプリが
// 確立した「白背景+単色シルエット、Mac版と別色」の慣例には従わず、
// **MyGames(Mac版)と全く同じ意匠**(白背景+ファミコン実機の実写配色コントローラー、
// mygames/make-icon.swiftと同じ配色・レイアウト)を流用する。
// iOSのApp Iconはシステム側で自動的に角丸マスクをかけるため、Mac版と違い
// 手動では角丸を描かず正方形いっぱいに背景を塗り、1024x1024の1枚のPNGだけを
// Assets.xcassets/AppIcon.appiconset/ に出力する(icns/iconsetは作らない)。
//   実行: swift make-icon.swift
//   → Sources/MyGamesPad/Assets.xcassets/AppIcon.appiconset/icon-1024.png を出力
import AppKit

let bgWhite = NSColor.white
let bodyGray = NSColor(calibratedWhite: 0.86, alpha: 1) // 本体(ファミコン実機の生成り色を簡略化したグレー)
let bodyOutline = NSColor.black // グレー本体を白背景から浮かせるための輪郭線
let dpadBlack = NSColor.black // 十字キー
let buttonRed = NSColor(calibratedRed: 0.702, green: 0.0, blue: 0.063, alpha: 1) // A/Bボタン(MyGames Mac版と同じ #B30010)

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
    let g = ctx.cgContext

    // 背景 — iOS側で角丸マスクがかかるため正方形いっぱいに塗る
    bgWhite.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s)).fill()

    let cx = s * 0.5
    let cy = s * 0.5

    // Controller body — flat gray rectangle with a thin black outline
    let bodyW = s * 0.66
    let bodyH = s * 0.24
    let bodyRect = CGRect(x: cx - bodyW / 2, y: cy - bodyH / 2, width: bodyW, height: bodyH)
    let bodyRadius = bodyH * 0.12
    let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil)
    g.setFillColor(bodyGray.cgColor)
    g.addPath(bodyPath)
    g.fillPath()
    g.setStrokeColor(bodyOutline.cgColor)
    g.setLineWidth(s * 0.008)
    g.addPath(bodyPath)
    g.strokePath()

    // D-pad (left side) — black cross
    let dpadCx = cx - bodyW * 0.28
    let dpadCy = cy
    let dpadArm = s * 0.032
    let dpadLen = s * 0.048
    g.setFillColor(dpadBlack.cgColor)
    g.fill(CGRect(x: dpadCx - dpadLen, y: dpadCy - dpadArm / 2, width: dpadLen * 2, height: dpadArm))
    g.fill(CGRect(x: dpadCx - dpadArm / 2, y: dpadCy - dpadLen, width: dpadArm, height: dpadLen * 2))

    // A / B buttons (right side) — round and red, side by side at the same height
    let btnCy = cy
    let btnR = s * 0.032
    let btnGap = s * 0.045
    let btnCxB = cx + bodyW * 0.19
    let btnCxA = cx + bodyW * 0.19 + btnGap + btnR * 2
    g.setFillColor(buttonRed.cgColor)
    g.fillEllipse(in: CGRect(x: btnCxB - btnR, y: btnCy - btnR, width: btnR * 2, height: btnR * 2))
    g.fillEllipse(in: CGRect(x: btnCxA - btnR, y: btnCy - btnR, width: btnR * 2, height: btnR * 2))

    // SELECT / START — small black rects centered between the D-pad and buttons
    let smallW = s * 0.05
    let smallH = s * 0.014
    let smallY = cy - smallH / 2
    g.setFillColor(dpadBlack.cgColor)
    g.fill(CGRect(x: cx - smallW - s * 0.012, y: smallY, width: smallW, height: smallH))
    g.fill(CGRect(x: cx + s * 0.012, y: smallY, width: smallW, height: smallH))

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

let outDir = "Sources/MyGamesPad/Assets.xcassets/AppIcon.appiconset"
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
savePNG(renderIcon(pixels: 1024), to: "\(outDir)/icon-1024.png")
print("✅ icon-1024.png を生成しました")
