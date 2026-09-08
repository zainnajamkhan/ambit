//
//  make-icon.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//
//  Draws the app icon and writes an .icns. Run with:  swift Tools/make-icon.swift
//
//  Drawn rather than assembled from a symbol font, because the SF Symbols licence forbids
//  using SF Symbols in an app icon. That fact cost Quiet real time; it is written down in
//  its knowledge base and it applies here too.
//
//  The mark: a ring divided into arcs of unequal length. "Ambit" means the extent or
//  circumference of something, and the ring is literally that. It is also the day ribbon
//  from inside the app, bent into a circle: segments of a day, some long, some brief, with
//  gaps where you were away. One idea, carried from the name through the interface to the
//  icon.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

/// Deep slate, so the icon holds together against any wallpaper, with the app's teal on it.
let backgroundTop = CGColor(srgbRed: 0.13, green: 0.17, blue: 0.19, alpha: 1)
let backgroundBottom = CGColor(srgbRed: 0.07, green: 0.10, blue: 0.12, alpha: 1)
let teal = CGColor(srgbRed: 0.36, green: 0.80, blue: 0.76, alpha: 1)
let tealDim = CGColor(srgbRed: 0.24, green: 0.55, blue: 0.55, alpha: 1)
let sand = CGColor(srgbRed: 0.96, green: 0.80, blue: 0.45, alpha: 1)
// Light enough that the gaps read as unused track rather than as holes punched
// through the icon, which is how a darker track looked.
let trackColour = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16)

/// One arc of the ring: where it starts, how long it runs, what colour.
/// Deliberately uneven, because an evenly divided ring reads as a pie chart or a loading
/// spinner, and this is meant to read as a day.
struct Arc {
    let start: CGFloat
    let sweep: CGFloat
    let colour: CGColor
}

//
// Four segments, not five, and butt caps rather than round ones.
//
// The first attempt used round caps, which at this thickness extend each arc by about
// nineteen degrees at either end. The segments ran into each other and the whole thing
// read as a loading spinner at full size and as a smudge at thirty two points. Square ends
// with real gaps between them survive being small, which is the only size most people will
// ever see this at.
//
// The lengths are deliberately lopsided: one long morning, two shorter stretches, one brief
// accent. An evenly divided ring is a pie chart.
let arcs: [Arc] = [
    Arc(start: -84, sweep: 128, colour: teal),
    Arc(start: 56, sweep: 66, colour: tealDim),
    Arc(start: 134, sweep: 34, colour: sand),
    Arc(start: 180, sweep: 52, colour: teal),
]

// MARK: - Drawing

func drawIcon(size: CGFloat) -> CGImage? {
    let scale: CGFloat = size / 1024
    guard let context = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS icons are not edge to edge. The art sits in the middle with breathing room, or
    // it looks oversized next to every other icon in the Dock.
    let inset: CGFloat = 100
    let plate = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
    let squircle = CGPath(roundedRect: plate, cornerWidth: 190, cornerHeight: 190, transform: nil)

    context.saveGState()
    context.addPath(squircle)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [backgroundTop, backgroundBottom] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: plate.maxY),
            end: CGPoint(x: 0, y: plate.minY),
            options: []
        )
    }
    context.restoreGState()

    // A hairline along the top edge, the way physical things catch light. Subtle enough to
    // read as material rather than as a border.
    context.saveGState()
    context.addPath(squircle)
    context.setLineWidth(3)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
    context.strokePath()
    context.restoreGState()

    let centre = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 228
    // Thick enough to survive being drawn at sixteen points, where a delicate ring becomes
    // a grey smudge. The hole stays open enough to read as a ring rather than a disc.
    let thickness: CGFloat = 112

    func stroke(from startDegrees: CGFloat, sweep: CGFloat, colour: CGColor, width: CGFloat) {
        context.saveGState()
        context.setLineCap(.butt)
        context.setLineWidth(width)
        context.setStrokeColor(colour)
        context.addArc(
            center: centre,
            radius: radius,
            startAngle: startDegrees * .pi / 180,
            endAngle: (startDegrees + sweep) * .pi / 180,
            clockwise: false
        )
        context.strokePath()
        context.restoreGState()
    }

    // The unused part of the ring, so the segments read as parts of a whole day rather than
    // as free floating shapes.
    stroke(from: 0, sweep: 360, colour: trackColour, width: thickness)
    for arc in arcs {
        stroke(from: arc.start, sweep: arc.sweep, colour: arc.colour, width: thickness)
    }

    return context.makeImage()
}

// MARK: - Writing

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/Ambit.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let image = drawIcon(size: variant.size) else {
        FileHandle.standardError.write(Data("failed at \(variant.name)\n".utf8))
        exit(1)
    }
    let url = iconset.appendingPathComponent("\(variant.name).png")
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    ) else { exit(1) }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

// The 1024 master, kept for the App Store listing, which wants it separately.
if let master = drawIcon(size: 1024) {
    let url = root.appendingPathComponent("build/AmbitIcon-1024.png")
    if let destination = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    ) {
        CGImageDestinationAddImage(destination, master, nil)
        CGImageDestinationFinalize(destination)
    }
}

print("wrote \(iconset.path)")
