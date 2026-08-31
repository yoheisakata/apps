#!/usr/bin/env swift
// 白い角丸スクエアに黒の「写真」プレート(山+太陽のシルエットを白で切り抜いた、
// 定番の画像アイコンのモチーフ)を描いた macOS アプリアイコンを生成する。
// mygames/mymusic/mytube/mygallery と同じ「白背景 + 単色シルエット」構成、
// シルエット色(黒)も共通(自作アプリでファミリー感を揃えている)。
// mytubeの再生三角形プレートと紛らわしくならないよう、モチーフ自体は「写真」を表す
// 山+太陽にして視覚的に区別している。
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

    // 中央に赤い角丸長方形(写真のプレート)。中に山+太陽のシルエットを背景色(白)でくり抜く。
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
    silhouetteBlack.setFill()
    plate.fill()

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
