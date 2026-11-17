// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo
//
// Draws the Brew GUI app icon (a beer mug with a checklist – the Brewfile) as a 1024×1024 PNG.
// Run via scripts/icon/make-icon.sh, which also builds AppIcon.icns.

import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Rectangles are given in top-left based coordinates (like a design tool) and flipped here.
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: size - y - h, width: w, height: h)
}

func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: size - y) }

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: macOS icon shape (824 pt body on a 1024 canvas) with a soft shadow.
let body = NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 186, yRadius: 186)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0x000000, 0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
color(0x173A5E).setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0x2C5F8A), ending: color(0x0E2440))!.draw(in: body, angle: -90)

// Handle (drawn first, behind the glass).
let handle = NSBezierPath(roundedRect: rect(590, 420, 210, 300), xRadius: 105, yRadius: 105)
handle.appendRoundedRect(rect(640, 478, 110, 184), xRadius: 55, yRadius: 55)
handle.windingRule = .evenOdd
color(0xE9F1F7, 0.92).setFill()
handle.fill()

// Glass: beer with a darker bottom, a light rim and a reflection.
let glass = NSBezierPath(roundedRect: rect(240, 330, 400, 500), xRadius: 56, yRadius: 56)
NSGradient(colors: [color(0xFFC94A), color(0xF5A623), color(0xD9780F)])!.draw(in: glass, angle: -90)
color(0xFFFFFF, 0.55).setStroke()
glass.lineWidth = 14
glass.stroke()
let shine = NSBezierPath(roundedRect: rect(272, 380, 34, 400), xRadius: 17, yRadius: 17)
color(0xFFFFFF, 0.28).setFill()
shine.fill()

// Bubbles.
color(0xFFF3C4, 0.55).setFill()
for (x, y, r) in [(590.0, 760.0, 11.0), (565, 700, 8), (600, 640, 7), (300, 805, 9), (580, 805, 6)] {
    NSBezierPath(ovalIn: rect(x - r, y - r, r * 2, r * 2)).fill()
}

// Checklist on the glass – the Brewfile.
for (index, y) in [450.0, 550.0, 650.0].enumerated() {
    let box = NSBezierPath(roundedRect: rect(318, y - 30, 60, 60), xRadius: 16, yRadius: 16)
    color(0xFFFFFF, 0.95).setFill()
    box.fill()
    let check = NSBezierPath()
    check.move(to: point(333, y + 1))
    check.line(to: point(345, y + 13))
    check.line(to: point(364, y - 12))
    check.lineWidth = 11
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    color(0xD9780F).setStroke()
    check.stroke()
    let width: CGFloat = [190, 150, 175][index]
    color(0xFFFFFF, 0.9).setFill()
    NSBezierPath(roundedRect: rect(404, y - 14, width, 28), xRadius: 14, yRadius: 14).fill()
}

// Foam: overlapping circles over the rim, with a little drip.
let foam = NSBezierPath()
for (x, y, r) in [(270.0, 330.0, 62.0), (360, 300, 82), (470, 292, 88), (575, 318, 70), (632, 350, 48)] {
    foam.appendOval(in: rect(x - r, y - r, r * 2, r * 2))
}
foam.appendRoundedRect(rect(212, 316, 456, 66), xRadius: 33, yRadius: 33)
foam.appendRoundedRect(rect(560, 330, 46, 110), xRadius: 23, yRadius: 23)
NSGraphicsContext.saveGraphicsState()
let foamShadow = NSShadow()
foamShadow.shadowColor = color(0x7A4A12, 0.35)
foamShadow.shadowBlurRadius = 10
foamShadow.shadowOffset = NSSize(width: 0, height: -6)
foamShadow.set()
color(0xFFFBF0).setFill()
foam.fill()
NSGraphicsContext.restoreGraphicsState()
color(0xFFFFFF, 0.8).setFill()
NSBezierPath(ovalIn: rect(410, 240, 70, 34)).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
