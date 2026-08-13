#!/usr/bin/env swift
// 白背景に濃い赤のシルエットで音符(八分音符)を描いた macOS アプリアイコンを生成する。
// mygames と同じ「白背景 + 単色シルエット」構成で、シルエット色(黒みのある濃い赤)は
// mygames/mytube/mygallery と共通(自作アプリでファミリー感を揃えている)。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let bgWhite = NSColor.white
let silhouetteRed = NSColor(srgbRed: 0.70, green: 0.0, blue: 0.06, alpha: 1) // 黒みを足した濃い赤 (mygames と共通)

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

    // 八分音符: 2つの符頭 + 符幹 + 連桁。
    silhouetteRed.setFill()

    let headW = s * 0.17
    let headH = s * 0.13
    let stemW = s * 0.035
    let stemH = s * 0.40

    // 符幹が上へ伸びる分を見込んで符頭を下寄りに置き、シルエット全体の重心をアイコン中央に合わせる。
    let leftHeadCenter = NSPoint(x: rect.midX - s * 0.12, y: rect.midY - s * 0.21)
    let rightHeadCenter = NSPoint(x: rect.midX + s * 0.12, y: rect.midY - s * 0.13)

    func drawHead(at center: NSPoint) {
        let headRect = NSRect(x: center.x - headW / 2, y: center.y - headH / 2, width: headW, height: headH)
        NSBezierPath(ovalIn: headRect).fill()
    }
    drawHead(at: leftHeadCenter)
    drawHead(at: rightHeadCenter)

    let leftStemRect = NSRect(x: leftHeadCenter.x + headW / 2 - stemW, y: leftHeadCenter.y, width: stemW, height: stemH)
    let rightStemRect = NSRect(x: rightHeadCenter.x + headW / 2 - stemW, y: rightHeadCenter.y, width: stemW, height: stemH)
    NSBezierPath(rect: leftStemRect).fill()
    NSBezierPath(rect: rightStemRect).fill()

    // 連桁(2本の符幹の頂点をつなぐ太い帯)。
    let beam = NSBezierPath()
    let beamH = s * 0.06
    beam.move(to: NSPoint(x: leftStemRect.minX, y: leftStemRect.maxY))
    beam.line(to: NSPoint(x: rightStemRect.maxX, y: rightStemRect.maxY))
    beam.line(to: NSPoint(x: rightStemRect.maxX, y: rightStemRect.maxY - beamH))
    beam.line(to: NSPoint(x: leftStemRect.minX, y: leftStemRect.maxY - beamH))
    beam.close()
    beam.fill()

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
