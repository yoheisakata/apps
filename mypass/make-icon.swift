#!/usr/bin/env swift
// 白背景に紫のドル袋（口をひもで結んだ袋＋中央の白い「$」）を描いたアイコンを生成する。
//   実行: swift make-icon.swift   →  AppIcon.icns と AppIcon.iconset/ を出力
import AppKit

let purpleBottom = NSColor(srgbRed: 0.36, green: 0.20, blue: 0.70, alpha: 1)

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let s = CGFloat(pixels)
    let inset = s * 0.08
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // 白背景（シンボルは紫）
    NSColor.white.setFill()
    path.fill()

    let cx = s / 2

    // ── 袋の本体: 上がすぼまり（口の下のくびれ）、下がふくらんだ形。
    // 上端 0.66s（口）→ 下端 0.17s（底）。
    let bag = CGMutablePath()
    bag.move(to: CGPoint(x: cx - s * 0.13, y: s * 0.66))
    bag.addCurve(to: CGPoint(x: cx - s * 0.31, y: s * 0.17),
                 control1: CGPoint(x: cx - s * 0.20, y: s * 0.58),
                 control2: CGPoint(x: cx - s * 0.36, y: s * 0.38))
    bag.addQuadCurve(to: CGPoint(x: cx + s * 0.31, y: s * 0.17),
                     control: CGPoint(x: cx, y: s * 0.13))
    bag.addCurve(to: CGPoint(x: cx + s * 0.13, y: s * 0.66),
                 control1: CGPoint(x: cx + s * 0.36, y: s * 0.38),
                 control2: CGPoint(x: cx + s * 0.20, y: s * 0.58))
    bag.closeSubpath()

    cg.setFillColor(purpleBottom.cgColor)
    cg.addPath(bag)
    cg.fillPath()

    // ── 口のひも: 袋の口に巻いた帯（白い縁取りで袋との境目を見せる）
    let bandRect = CGRect(x: cx - s * 0.17, y: s * 0.625, width: s * 0.34, height: s * 0.07)
    let bandPath = CGPath(roundedRect: bandRect, cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil)
    cg.setStrokeColor(NSColor.white.cgColor)
    cg.setLineWidth(s * 0.02)
    cg.addPath(bandPath)
    cg.strokePath()
    cg.setFillColor(purpleBottom.cgColor)
    cg.addPath(bandPath)
    cg.fillPath()

    // ── 結び目のリボン: 左右の輪（ひねった楕円）と中央の結び目
    let loopSize = CGSize(width: s * 0.11, height: s * 0.065)
    for (dx, angle) in [(-0.065, CGFloat.pi / 7), (0.065, -CGFloat.pi / 7)] {
        cg.saveGState()
        cg.translateBy(x: cx + s * CGFloat(dx), y: s * 0.745)
        cg.rotate(by: angle)
        cg.setFillColor(purpleBottom.cgColor)
        cg.fillEllipse(in: CGRect(x: -loopSize.width / 2, y: -loopSize.height / 2,
                                  width: loopSize.width, height: loopSize.height))
        cg.restoreGState()
    }
    cg.setFillColor(purpleBottom.cgColor)
    cg.fillEllipse(in: CGRect(x: cx - s * 0.035, y: s * 0.70, width: s * 0.07, height: s * 0.07))

    // ── 中央の「$」（白）
    let dollar = "$" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s * 0.42, weight: .heavy),
        .foregroundColor: NSColor.white,
    ]
    let size = dollar.size(withAttributes: attrs)
    dollar.draw(at: NSPoint(x: cx - size.width / 2, y: s * 0.40 - size.height / 2),
                withAttributes: attrs)

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
