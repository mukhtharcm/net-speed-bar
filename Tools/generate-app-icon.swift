#!/usr/bin/swift

import AppKit
import Foundation

let arguments = CommandLine.arguments

guard arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = CGSize(width: 1024, height: 1024)

let image = NSImage(size: canvasSize)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("Unable to create graphics context.\n", stderr)
    exit(1)
}

let rect = CGRect(origin: .zero, size: canvasSize)
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

func drawRoundedBackground() {
    let panelRect = rect.insetBy(dx: 42, dy: 42)
    let path = NSBezierPath(roundedRect: panelRect, xRadius: 220, yRadius: 220)
    path.addClip()
    let gradient = NSGradient(colors: [
        color(8, 15, 36),
        color(15, 43, 84),
        color(28, 89, 132)
    ])!
    gradient.draw(in: path, angle: -55)

    color(255, 255, 255, 0.08).setStroke()
    path.lineWidth = 6
    path.stroke()
}

func drawWaveBands() {
    let bandColors = [
        color(56, 189, 248, 0.18),
        color(45, 212, 191, 0.18),
        color(167, 243, 208, 0.14)
    ]

    for (index, bandColor) in bandColors.enumerated() {
        let offset = CGFloat(index) * 82
        let bandRect = CGRect(x: 130, y: 170 + offset, width: 764, height: 210)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bandRect.minX, y: bandRect.midY))

        let segments = 6
        let width = bandRect.width / CGFloat(segments)
        for segment in 0...segments {
            let x = bandRect.minX + CGFloat(segment) * width
            let phase = CGFloat(segment) * 0.9 + CGFloat(index) * 0.55
            let y = bandRect.midY + sin(phase) * (32 + CGFloat(index) * 10)
            path.line(to: CGPoint(x: x, y: y))
        }

        path.line(to: CGPoint(x: bandRect.maxX, y: bandRect.maxY))
        path.line(to: CGPoint(x: bandRect.minX, y: bandRect.maxY))
        path.close()

        bandColor.setFill()
        path.fill()
    }
}

func drawGauge() {
    let center = CGPoint(x: 512, y: 550)
    let radius: CGFloat = 268

    let outerArc = NSBezierPath()
    outerArc.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 200,
        endAngle: -20,
        clockwise: true
    )
    outerArc.lineWidth = 54
    outerArc.lineCapStyle = .round
    color(255, 255, 255, 0.12).setStroke()
    outerArc.stroke()

    let activeArc = NSBezierPath()
    activeArc.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 200,
        endAngle: 18,
        clockwise: true
    )
    activeArc.lineWidth = 54
    activeArc.lineCapStyle = .round

    context.saveGState()
    activeArc.addClip()
    let activeGradient = NSGradient(colors: [
        color(52, 211, 153),
        color(34, 197, 94),
        color(250, 204, 21)
    ])!
    activeGradient.draw(in: CGRect(x: 180, y: 220, width: 664, height: 664), angle: 0)
    context.restoreGState()

    for marker in 0...6 {
        let angle = CGFloat(200 - (marker * 36))
        let radians = angle * .pi / 180
        let inner = CGPoint(
            x: center.x + cos(radians) * (radius - 70),
            y: center.y + sin(radians) * (radius - 70)
        )
        let outer = CGPoint(
            x: center.x + cos(radians) * (radius - 16),
            y: center.y + sin(radians) * (radius - 16)
        )

        context.saveGState()
        context.setStrokeColor(color(230, 244, 255, 0.55).cgColor)
        context.setLineWidth(12)
        context.setLineCap(.round)
        context.move(to: inner)
        context.addLine(to: outer)
        context.strokePath()
        context.restoreGState()
    }

    let needleAngle = CGFloat(22) * .pi / 180
    let needleEnd = CGPoint(
        x: center.x + cos(needleAngle) * (radius - 86),
        y: center.y + sin(needleAngle) * (radius - 86)
    )

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 20, color: color(7, 12, 25, 0.35).cgColor)
    context.setStrokeColor(color(255, 244, 214).cgColor)
    context.setLineWidth(22)
    context.setLineCap(.round)
    context.move(to: center)
    context.addLine(to: needleEnd)
    context.strokePath()
    context.restoreGState()

    color(255, 244, 214).setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)).fill()
}

func drawType() {
    let down = NSAttributedString(
        string: "↓ 128",
        attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 124, weight: .bold),
            .foregroundColor: color(244, 250, 255)
        ]
    )

    let up = NSAttributedString(
        string: "↑ 18",
        attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 84, weight: .semibold),
            .foregroundColor: color(190, 236, 255, 0.95)
        ]
    )

    let unit = NSAttributedString(
        string: "MB/s",
        attributes: [
            .font: NSFont.systemFont(ofSize: 54, weight: .medium),
            .foregroundColor: color(190, 236, 255, 0.9)
        ]
    )

    down.draw(at: CGPoint(x: 248, y: 160))
    up.draw(at: CGPoint(x: 320, y: 82))
    unit.draw(at: CGPoint(x: 570, y: 187))
}

drawRoundedBackground()
drawWaveBands()
drawGauge()
drawType()

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Unable to encode icon image.\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("Failed to write icon image: \(error)\n", stderr)
    exit(1)
}
