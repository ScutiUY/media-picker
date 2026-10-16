// 앱 아이콘을 코드로 그린다: swift Icon/make-icon.swift <출력 폴더>
// 겹친 카드(재생할 수 있는 것들) 중 맨 앞의 고른 카드에 재생 표시.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(red: r, green: g, blue: b, alpha: a).cgColor
}

func gradient(_ top: CGColor, _ bottom: CGColor) -> CGGradient {
    CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
}

/// 모서리가 둥근 재생 삼각형
func playTriangle(_ ctx: CGContext, center: CGPoint, height h: CGFloat) {
    let w = h * 0.87
    let t = CGMutablePath()
    t.move(to: CGPoint(x: center.x - w / 3, y: center.y + h / 2))
    t.addLine(to: CGPoint(x: center.x + 2 * w / 3, y: center.y))
    t.addLine(to: CGPoint(x: center.x - w / 3, y: center.y - h / 2))
    t.closeSubpath()
    ctx.addPath(t)
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.setStrokeColor(rgb(1, 1, 1))
    ctx.setLineWidth(h * 0.12)
    ctx.setLineJoin(.round)
    ctx.drawPath(using: .fillStroke)
}

func render(_ size: Int, margin: Bool = true) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    // macOS 아이콘 격자: 1024 캔버스 안에 824 크기의 둥근 사각형
    let inset: CGFloat = margin ? 100 : 0
    let body = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
    let radius = body.width * 0.225
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    if margin {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.35))
        ctx.addPath(bodyPath)
        ctx.setFillColor(rgb(0, 0, 0))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient(rgb(0.20, 0.13, 0.36), rgb(0.08, 0.06, 0.16)),
                           start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])

    // 뒤의 두 장: 고르지 않은 다른 미디어
    let card = CGSize(width: 500, height: 420)
    for (i, (angle, alpha)) in [(-16.0, 0.16), (-8.0, 0.28)].enumerated() {
        let shift = CGFloat(2 - i)
        ctx.saveGState()
        ctx.translateBy(x: 512, y: 512)
        ctx.rotate(by: angle * .pi / 180)
        ctx.translateBy(x: -512 - shift * 40, y: -512 + shift * 34)
        let rect = CGRect(origin: CGPoint(x: 262, y: 300), size: card)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 70, cornerHeight: 70, transform: nil))
        ctx.setFillColor(rgb(1, 1, 1, alpha))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 맨 앞: 고른 미디어
    let front = CGRect(origin: CGPoint(x: 292, y: 270), size: card)
    let frontPath = CGPath(roundedRect: front, cornerWidth: 70, cornerHeight: 70, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0, 0, 0, 0.5))
    ctx.addPath(frontPath)
    ctx.setFillColor(rgb(0.12, 0.38, 0.95))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(frontPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient(rgb(0.27, 0.58, 1.0), rgb(0.12, 0.38, 0.95)),
                           start: CGPoint(x: 0, y: front.maxY), end: CGPoint(x: 0, y: front.minY), options: [])
    ctx.restoreGState()
    playTriangle(ctx, center: CGPoint(x: front.midX - 8, y: front.midY), height: 190)

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// .iconset (iconutil이 .icns로 묶는다)
let iconset = "\(out)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    save(render(base), "\(iconset)/icon_\(base)x\(base).png")
    save(render(base * 2), "\(iconset)/icon_\(base)x\(base)@2x.png")
}
save(render(1024), "\(out)/icon-1024.png")
// 브라우저 확장 아이콘은 여백 없이 꽉 채운다.
for size in [16, 32, 48, 128] {
    save(render(size, margin: false), "\(out)/extension-\(size).png")
}
