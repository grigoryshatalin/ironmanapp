#!/usr/bin/env swift
//
// Generates the Endurance app icon per ICON_SPEC.md Concept A,
// "Continuous line": one unbroken stroke that reads as forward motion —
// a shallow wave (swim) flowing into a smooth arc (bike) and finishing with a
// slight kick up (run) — on a near-flat vertical wash.
//
// Kept as a script so the mark is reproducible and reviewable as code rather
// than an opaque binary. Run:  swift Tools/GenerateAppIcon.swift <output.png>
//
import AppKit

let side = 1024.0
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"

guard let context = CGContext(
    data: nil,
    width: Int(side), height: Int(side),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Could not create bitmap context") }

// MARK: Background — a calm, near-flat vertical wash.
// The two stops sit within a few percent luminance so it reads as flat at a
// glance, per the spec's explicit warning against saturated gradients.
let top = CGColor(srgbRed: 0.113, green: 0.325, blue: 0.396, alpha: 1)     // muted teal-blue
let bottom = CGColor(srgbRed: 0.075, green: 0.243, blue: 0.310, alpha: 1)  // a touch deeper
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [top, bottom] as CFArray,
    locations: [0, 1])!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: side),
    end: CGPoint(x: 0, y: 0),
    options: [])

// MARK: The mark — one unbroken path, single weight, rounded caps.
// Geometry is expressed in normalized units so the proportions are legible and
// the whole mark stays optically centred. Stroke weight is deliberately light:
// heavier than ~6% of the canvas and the opening wave self-merges into a blob
// at small sizes, which defeats the "readable at 40px" requirement.
func p(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: side * x, y: side * y)
}

let stroke = side * 0.052
context.setLineWidth(stroke)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96))

let path = CGMutablePath()
path.move(to: p(0.16, 0.33))

// 1. Swim — a shallow wave, amplitude kept under the stroke's own diameter so
//    the curve stays open rather than fusing.
path.addCurve(to: p(0.40, 0.415),
              control1: p(0.235, 0.395),
              control2: p(0.315, 0.315))

// 2. Bike — a long, steady arc: the calm middle of the day.
path.addCurve(to: p(0.665, 0.545),
              control1: p(0.475, 0.475),
              control2: p(0.565, 0.545))

// 3. Run — a final, unmistakable kick upward to the finish.
path.addCurve(to: p(0.84, 0.67),
              control1: p(0.745, 0.545),
              control2: p(0.795, 0.60))

context.addPath(path)
context.strokePath()

guard let image = context.makeImage() else { fatalError("Could not render image") }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: side, height: side)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath) at \(Int(side))×\(Int(side))")
