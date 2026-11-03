// gen_icons.swift
// 图标生成工具:绘制状态栏模板图标与 App 图标
// 运行:swift Tools/gen_icons.swift <输出目录>

import AppKit

let outRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let assetsDir = outRoot.appendingPathComponent("Assets", isDirectory: true)
let iconsetDir = outRoot.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// MARK: - 位图上下文

func renderBitmap(pixels: Int, draw: () -> Void) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else {
        fatalError("无法创建位图")
    }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.setAllowsAntialiasing(true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

// MARK: - 剪切板图形

/// 在 rect 内绘制剪切板轮廓:外框 + 顶部夹子 + 三条历史线
func drawClipboardGlyph(in rect: NSRect, color: NSColor, showLines: Bool = true) {
    let w = rect.width
    let h = rect.height
    let lineWidth = max(1.0, w * 0.078)

    color.setStroke()

    // 外框
    let body = NSRect(x: rect.minX + w * 0.20,
                      y: rect.minY + h * 0.07,
                      width: w * 0.60,
                      height: h * 0.80)
    let bodyPath = NSBezierPath(roundedRect: body,
                                xRadius: w * 0.095,
                                yRadius: w * 0.095)
    bodyPath.lineWidth = lineWidth
    bodyPath.stroke()

    // 顶部夹子
    let clipRect = NSRect(x: rect.midX - w * 0.115,
                          y: rect.minY + h * 0.79,
                          width: w * 0.23,
                          height: h * 0.13)
    let clipPath = NSBezierPath(roundedRect: clipRect,
                                xRadius: w * 0.04,
                                yRadius: w * 0.04)
    clipPath.lineWidth = lineWidth
    clipPath.stroke()

    // 内部历史线
    if showLines {
        for ratio in [0.58, 0.41, 0.24] {
            let y = rect.minY + h * CGFloat(ratio)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: rect.minX + w * 0.35, y: y))
            line.line(to: NSPoint(x: rect.minX + w * 0.65, y: y))
            line.lineWidth = lineWidth * 0.75
            line.lineCapStyle = .round
            line.stroke()
        }
    }
}

// MARK: - 状态栏图标(模板图,纯黑 + alpha,由系统自动适配深浅色)

for (pixels, name) in [(18, "StatusIcon.png"), (36, "StatusIcon@2x.png")] {
    let rep = renderBitmap(pixels: pixels) {
        let inset = CGFloat(pixels) * 0.075
        let rect = NSRect(x: inset, y: inset,
                          width: CGFloat(pixels) - inset * 2,
                          height: CGFloat(pixels) - inset * 2)
        drawClipboardGlyph(in: rect, color: .black)
    }
    writePNG(rep, to: assetsDir.appendingPathComponent(name))
}

// MARK: - App 图标

/// 绘制一枚 App 图标:圆角渐变底 + 白色剪切板图形
func drawAppIcon(pixels: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    return renderBitmap(pixels: pixels) {
        let inset = size * 0.09
        let bgRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let radius = (size - inset * 2) * 0.235

        // 底:蓝色 → 紫色渐变
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.36, green: 0.55, blue: 1.00, alpha: 1.00),
            NSColor(srgbRed: 0.52, green: 0.34, blue: 0.96, alpha: 1.00),
        ])!
        gradient.draw(in: bgPath, angle: -90)

        // 底部内高光,增加层次
        let highlight = NSBezierPath(roundedRect: bgRect.insetBy(dx: size * 0.012, dy: size * 0.012),
                                     xRadius: radius, yRadius: radius)
        NSColor(white: 1.0, alpha: 0.14).setStroke()
        highlight.lineWidth = size * 0.012
        highlight.stroke()

        // 白色剪切板图形
        let glyphSize = size * 0.46
        let glyphRect = NSRect(x: (size - glyphSize) / 2,
                               y: (size - glyphSize) / 2,
                               width: glyphSize,
                               height: glyphSize)
        drawClipboardGlyph(in: glyphRect, color: .white)
    }
}

let iconSizes: [(pixels: Int, name: String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for entry in iconSizes {
    let rep = drawAppIcon(pixels: entry.pixels)
    writePNG(rep, to: iconsetDir.appendingPathComponent(entry.name))
}

print("图标已生成:\(assetsDir.path)")
print("iconset 已生成:\(iconsetDir.path)")
