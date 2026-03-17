#!/usr/bin/env swift
/// Generates icon_1024.png using CGContext (headless-safe).
import CoreGraphics
import ImageIO
import Foundation

let size = 1024
let scale = 1
let w = size * scale
let h = size * scale
let s = CGFloat(w)

guard let ctx = CGContext(
    data: nil, width: w, height: h,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fputs("error: CGContext\n", stderr); exit(1) }

ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

// ── Background gradient ───────────────────────────────────────────────────
let cr = s * 0.225
let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
let bgPath = CGMutablePath()
bgPath.addRoundedRect(in: bgRect, cornerWidth: cr, cornerHeight: cr)
ctx.addPath(bgPath); ctx.clip()

let gradColors = [rgb(0.14, 0.14, 0.17), rgb(0.07, 0.07, 0.09)] as CFArray
let locs: [CGFloat] = [0, 1]
if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: gradColors, locations: locs) {
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0),
        options: [])
}
ctx.resetClip()

// Inner top rim
ctx.setStrokeColor(rgb(1, 1, 1, 0.09))
ctx.setLineWidth(2)
ctx.move(to:    CGPoint(x: cr,      y: s - 1))
ctx.addLine(to: CGPoint(x: s - cr,  y: s - 1))
ctx.strokePath()

// ── Shelf ────────────────────────────────────────────────────────────────
let shelfY = s * 0.415
let shelfX = s * 0.13
let shelfW = s * 0.74
let shelfH = s * 0.058
let blue   = rgb(0.24, 0.52, 0.98)
let blueDim = rgb(0.24, 0.52, 0.98, 0.50)

func roundedRect(_ r: CGRect, _ rx: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addRoundedRect(in: r, cornerWidth: rx, cornerHeight: rx)
    return p
}

ctx.addPath(roundedRect(CGRect(x: shelfX, y: shelfY, width: shelfW, height: shelfH), shelfH/2))
ctx.setFillColor(blue); ctx.fillPath()

// Shelf legs
let legW = s * 0.054
let legH = s * 0.185
ctx.setFillColor(blueDim)
for legX in [shelfX + shelfW * 0.10, shelfX + shelfW * 0.86] {
    ctx.addPath(roundedRect(
        CGRect(x: legX, y: shelfY - legH, width: legW, height: legH + shelfH * 0.4),
        legW / 2))
    ctx.fillPath()
}

// ── Files on shelf ────────────────────────────────────────────────────────
let fileW = s * 0.135
let fileH = s * 0.225
let fileY = shelfY + shelfH
let fc    = s * 0.022
let gap   = (shelfW - 3 * fileW) / 4

let fileColors: [CGColor] = [
    rgb(0.99, 0.45, 0.22),
    rgb(0.22, 0.72, 0.45),
    rgb(0.35, 0.57, 0.99),
]
let fileXPositions: [CGFloat] = [
    shelfX + gap,
    shelfX + gap * 2 + fileW,
    shelfX + gap * 3 + fileW * 2,
]

for i in 0..<3 {
    let fx = fileXPositions[i]
    let fileRect = CGRect(x: fx, y: fileY, width: fileW, height: fileH)

    // Body
    ctx.addPath(roundedRect(fileRect, fc))
    ctx.setFillColor(fileColors[i]); ctx.fillPath()

    // Dog-ear fold
    let fold = fileW * 0.28
    let earPath = CGMutablePath()
    earPath.move(to:    CGPoint(x: fx + fileW - fold, y: fileY + fileH))
    earPath.addLine(to: CGPoint(x: fx + fileW,        y: fileY + fileH - fold))
    earPath.addLine(to: CGPoint(x: fx + fileW,        y: fileY + fileH))
    earPath.closeSubpath()
    ctx.addPath(earPath)
    ctx.setFillColor(rgb(0, 0, 0, 0.20)); ctx.fillPath()

    // Content lines
    let lh = s * 0.013
    let lx = fx + fileW * 0.18
    ctx.setFillColor(rgb(1, 1, 1, 0.38))
    ctx.addPath(roundedRect(CGRect(x: lx, y: fileY + fileH * 0.47, width: fileW * 0.63, height: lh), lh/2))
    ctx.fillPath()
    ctx.addPath(roundedRect(CGRect(x: lx, y: fileY + fileH * 0.34, width: fileW * 0.45, height: lh), lh/2))
    ctx.fillPath()
}

// ── Subtle down-arrow above files ────────────────────────────────────────
// Draw a simple chevron manually (no SF Symbols in headless CGContext)
let arrowCX = s / 2
let arrowY  = fileY + fileH + s * 0.06
let arrowW  = s * 0.07
let arrowLH = s * 0.013

ctx.setStrokeColor(rgb(1, 1, 1, 0.22))
ctx.setLineWidth(arrowLH)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to:    CGPoint(x: arrowCX - arrowW / 2, y: arrowY + arrowW * 0.5))
ctx.addLine(to: CGPoint(x: arrowCX,              y: arrowY))
ctx.addLine(to: CGPoint(x: arrowCX + arrowW / 2, y: arrowY + arrowW * 0.5))
ctx.strokePath()

// ── Write PNG ─────────────────────────────────────────────────────────────
guard let cgImage = ctx.makeImage() else {
    fputs("error: makeImage\n", stderr); exit(1)
}
let outURL = URL(fileURLWithPath: "icon_1024.png") as CFURL
guard let dest = CGImageDestinationCreateWithURL(outURL, "public.png" as CFString, 1, nil) else {
    fputs("error: CGImageDestination\n", stderr); exit(1)
}
CGImageDestinationAddImage(dest, cgImage, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("error: finalize\n", stderr); exit(1)
}
print("✅ icon_1024.png")
