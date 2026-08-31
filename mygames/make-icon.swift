#!/usr/bin/env swift
// 白背景に黒のシルエットでゲームコントローラーを描いたアイコンを生成する。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let bgWhite = NSColor.white
let silhouetteBlack = NSColor.black // 黒 (自作アプリ共通)

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

    // Draw game controller as a black silhouette
    let g = ctx.cgContext
    let silhouette = silhouetteBlack.cgColor

    let cx = s * 0.5
    let cy = s * 0.545  // 本体+グリップ全体の重心が正方形の中央に来るよう補正

    // Controller body (rounded rectangle)
    let bodyW = s * 0.52
    let bodyH = s * 0.26
    let bodyRect = CGRect(x: cx - bodyW / 2, y: cy - bodyH / 2, width: bodyW, height: bodyH)
    let bodyRadius = bodyH * 0.4
    let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil)
    g.setFillColor(silhouette)
    g.addPath(bodyPath)
    g.fillPath()

    // Left grip
    let gripW = s * 0.12
    let gripH = s * 0.18
    let leftGripRect = CGRect(x: cx - bodyW / 2 - gripW * 0.15, y: cy - bodyH / 2 - gripH * 0.5, width: gripW, height: gripH)
    let gripPath = CGPath(roundedRect: leftGripRect, cornerWidth: gripW * 0.4, cornerHeight: gripW * 0.4, transform: nil)
    g.setFillColor(silhouette)
    g.addPath(gripPath)
    g.fillPath()

    // Right grip
    let rightGripRect = CGRect(x: cx + bodyW / 2 - gripW * 0.85, y: cy - bodyH / 2 - gripH * 0.5, width: gripW, height: gripH)
    let gripPath2 = CGPath(roundedRect: rightGripRect, cornerWidth: gripW * 0.4, cornerHeight: gripW * 0.4, transform: nil)
    g.addPath(gripPath2)
    g.fillPath()

    // D-pad (left side)
    let dpadCx = cx - s * 0.13
    let dpadCy = cy + s * 0.01
    let dpadArm = s * 0.035
    let dpadLen = s * 0.05
    g.setFillColor(bgWhite.cgColor)
    // Horizontal
    g.fill(CGRect(x: dpadCx - dpadLen, y: dpadCy - dpadArm / 2, width: dpadLen * 2, height: dpadArm))
    // Vertical
    g.fill(CGRect(x: dpadCx - dpadArm / 2, y: dpadCy - dpadLen, width: dpadArm, height: dpadLen * 2))

    // Action buttons (right side) — A, B, X, Y diamond
    let btnCx = cx + s * 0.13
    let btnCy = cy + s * 0.01
    let btnR = s * 0.025
    let btnSpacing = s * 0.045
    g.setFillColor(bgWhite.cgColor)
    // Top (X)
    g.fillEllipse(in: CGRect(x: btnCx - btnR, y: btnCy + btnSpacing - btnR, width: btnR * 2, height: btnR * 2))
    // Bottom (B)
    g.fillEllipse(in: CGRect(x: btnCx - btnR, y: btnCy - btnSpacing - btnR, width: btnR * 2, height: btnR * 2))
    // Left (Y)
    g.fillEllipse(in: CGRect(x: btnCx - btnSpacing - btnR, y: btnCy - btnR, width: btnR * 2, height: btnR * 2))
    // Right (A)
    g.fillEllipse(in: CGRect(x: btnCx + btnSpacing - btnR, y: btnCy - btnR, width: btnR * 2, height: btnR * 2))

    // Start/Select (small rounded rects in center)
    let smallW = s * 0.035
    let smallH = s * 0.015
    let smallY = cy - s * 0.02
    g.setFillColor(bgWhite.cgColor)
    g.fill(CGRect(x: cx - smallW - s * 0.01, y: smallY, width: smallW, height: smallH))
    g.fill(CGRect(x: cx + s * 0.01, y: smallY, width: smallW, height: smallH))

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
