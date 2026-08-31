#!/usr/bin/env swift
// 白背景にファミコン実機の配色(グレー本体+黒十字キー+赤A/Bボタン)で
// コントローラーを描いたアイコンを生成する。MyGames だけは意図的に
// 「5アプリ単色シルエット統一」から外れた多色アイコン(2026-08-30の方針への例外、ユーザー指示)。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let bgWhite = NSColor.white
let bodyGray = NSColor(calibratedWhite: 0.86, alpha: 1) // 本体(ファミコン実機の生成り色を簡略化したグレー)
let bodyOutline = NSColor.black // グレー本体を白背景から浮かせるための輪郭線
let dpadBlack = NSColor.black // 十字キー
let buttonRed = NSColor(calibratedRed: 0.702, green: 0.0, blue: 0.063, alpha: 1) // A/Bボタン(旧統一シルエット色 #B30010 を流用)

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
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    bgWhite.setFill()
    path.fill()

    // Draw a Famicom (ファミコン)-style controller in its real-life colors:
    // a flat, straight-edged rectangular pad with no side grips — unlike a
    // modern gamepad's contoured body — a black cross D-pad on the left, two
    // round red buttons side by side on the right, and small black
    // SELECT/START rects between.
    let g = ctx.cgContext

    let cx = s * 0.5
    let cy = s * 0.5

    // Controller body — flat gray rectangle with a thin black outline
    // (a white body would disappear against the white background)
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
    // Horizontal
    g.fill(CGRect(x: dpadCx - dpadLen, y: dpadCy - dpadArm / 2, width: dpadLen * 2, height: dpadArm))
    // Vertical
    g.fill(CGRect(x: dpadCx - dpadArm / 2, y: dpadCy - dpadLen, width: dpadArm, height: dpadLen * 2))

    // A / B buttons (right side) — round and red, side by side at the same height
    let btnCy = cy
    let btnR = s * 0.032
    let btnGap = s * 0.045
    let btnCxB = cx + bodyW * 0.19 // B (left)
    let btnCxA = cx + bodyW * 0.19 + btnGap + btnR * 2 // A (right)
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
