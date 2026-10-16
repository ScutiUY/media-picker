// 앱 아이콘을 코드로 그린다: swift Icon/make-icon.swift <출력 폴더>
// 선택 창을 본뜬 세 줄 목록, 그중 강조된 한 줄에 재생 표시.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func render(_ size: Int, margin: Bool = true) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)

    // macOS 아이콘 격자: 1024 캔버스 안에 824 크기의 둥근 사각형
    let inset: CGFloat = margin ? 100 : 0
    let body = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
    let radius = body.width * 0.225
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    if margin {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(bodyPath)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: space, colors: [
        NSColor(red: 0.16, green: 0.17, blue: 0.24, alpha: 1).cgColor,
        NSColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])

    // 목록 세 줄 (위에서부터). 가운데 줄이 강조된 항목.
    let rowW: CGFloat = 600, rowH: CGFloat = 150, gap: CGFloat = 42
    let x0 = (1024 - rowW) / 2
    let midY: CGFloat = 512 - rowH / 2
    let rows = [midY + rowH + gap, midY, midY - rowH - gap]
    for (i, y) in rows.enumerated() {
        let selected = i == 1
        // 고른 줄은 살짝 크게, 그림자를 줘서 떠 보이게
        let rect = selected
            ? CGRect(x: x0, y: y, width: rowW, height: rowH).insetBy(dx: -24, dy: -10)
            : CGRect(x: x0, y: y, width: rowW, height: rowH)
        let path = CGPath(roundedRect: rect, cornerWidth: 46, cornerHeight: 46, transform: nil)
        if selected {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.addPath(path)
            ctx.setFillColor(NSColor(red: 0.12, green: 0.38, blue: 0.95, alpha: 1).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.addPath(path)
        if selected {
            ctx.saveGState()
            ctx.clip()
            let blue = CGGradient(colorsSpace: space, colors: [
                NSColor(red: 0.27, green: 0.58, blue: 1.0, alpha: 1).cgColor,
                NSColor(red: 0.12, green: 0.38, blue: 0.95, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(blue, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
            ctx.restoreGState()
        } else {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
            ctx.fillPath()
        }

        // 왼쪽: 재생 표시(강조 줄) 또는 점, 오른쪽: 제목 막대
        let cy = rect.midY
        if selected {
            let t = CGMutablePath()
            let tx = rect.minX + 78
            t.move(to: CGPoint(x: tx, y: cy + 40))
            t.addLine(to: CGPoint(x: tx + 66, y: cy))
            t.addLine(to: CGPoint(x: tx, y: cy - 40))
            t.closeSubpath()
            ctx.addPath(t)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(14)
            ctx.setLineJoin(.round)
            ctx.drawPath(using: .fillStroke)
        } else {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.28).cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.minX + 70, y: cy - 22, width: 44, height: 44))
        }
        let barX = selected ? rect.minX + 194 : rect.minX + 170
        let barW = selected ? 330.0 : (i == 0 ? 280.0 : 230.0)
        let bar = CGRect(x: barX, y: cy - 17, width: barW, height: 34)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 17, cornerHeight: 17, transform: nil))
        ctx.setFillColor(NSColor.white.withAlphaComponent(selected ? 0.95 : 0.28).cgColor)
        ctx.fillPath()
    }
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
