#!/usr/bin/swift

import AppKit
import Foundation

let arguments = CommandLine.arguments

guard arguments.count == 2 else {
    fputs("Usage: generate-dmg-background.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = CGSize(width: 1280, height: 720)

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

let gradient = NSGradient(colors: [
    color(4, 12, 28),
    color(11, 28, 52),
    color(18, 55, 86)
])!
gradient.draw(in: rect, angle: -35)

for index in 0..<5 {
    let y = CGFloat(100 + index * 110)
    let wave = NSBezierPath()
    wave.move(to: CGPoint(x: 0, y: y))

    for point in stride(from: 0, through: 1280, by: 80) {
        let x = CGFloat(point)
        let phase = CGFloat(point) / 140 + CGFloat(index) * 0.75
        let nextY = y + sin(phase) * (18 + CGFloat(index) * 4)
        wave.line(to: CGPoint(x: x, y: nextY))
    }

    color(93, 232, 255, 0.11 - CGFloat(index) * 0.012).setStroke()
    wave.lineWidth = 5
    wave.stroke()
}

let headline = NSAttributedString(
    string: "Net Speed Bar",
    attributes: [
        .font: NSFont.systemFont(ofSize: 54, weight: .bold),
        .foregroundColor: color(242, 248, 255)
    ]
)
headline.draw(at: CGPoint(x: 90, y: 585))

let subhead = NSAttributedString(
    string: "Live network throughput in your macOS menu bar",
    attributes: [
        .font: NSFont.systemFont(ofSize: 28, weight: .medium),
        .foregroundColor: color(196, 226, 244, 0.92)
    ]
)
subhead.draw(at: CGPoint(x: 92, y: 535))

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Unable to encode image.\n", stderr)
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
    fputs("Failed to write image: \(error)\n", stderr)
    exit(1)
}
