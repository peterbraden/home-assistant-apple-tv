#!/usr/bin/env swift
// Draws the tvOS app icon layers and Top Shelf images into the asset catalog.
//
//   swift scripts/generate-icons.swift
//
// The icon is three layers so tvOS can animate parallax: a blue gradient back,
// a soft glow in the middle, and a house with a rising graph in front.

import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let brandAssets = root.appendingPathComponent("App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets")

// MARK: - Palette

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let skyTop = rgb(0x29B6F6)
let skyBottom = rgb(0x0D47A1)
let glow = rgb(0xFFFFFF, 0.22)
let houseColor = rgb(0xFFFFFF)
let graphColor = rgb(0xFFC107)

// MARK: - Drawing

func makeContext(width: Int, height: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    return context
}

func drawBackground(_ context: CGContext, _ size: CGSize) {
    let gradient = CGGradient(colorsSpace: nil, colors: [skyTop, skyBottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size.height),
        end: CGPoint(x: size.width, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

func drawGlow(_ context: CGContext, center: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: nil, colors: [glow, rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(
        gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: []
    )
}

/// A house outline with a rising line graph inside, fitted to `height` and centred on `center`.
func drawHouse(_ context: CGContext, center: CGPoint, height: CGFloat) {
    let width = height * 1.0
    let line = height * 0.075
    let left = center.x - width / 2, right = center.x + width / 2
    let bottom = center.y - height / 2, top = center.y + height / 2
    let eaves = bottom + height * 0.56

    // House: walls and roof as one stroked path.
    let house = CGMutablePath()
    house.move(to: CGPoint(x: left + width * 0.12, y: eaves))
    house.addLine(to: CGPoint(x: left + width * 0.12, y: bottom))
    house.addLine(to: CGPoint(x: right - width * 0.12, y: bottom))
    house.addLine(to: CGPoint(x: right - width * 0.12, y: eaves))
    house.move(to: CGPoint(x: left, y: eaves - height * 0.04))
    house.addLine(to: CGPoint(x: center.x, y: top))
    house.addLine(to: CGPoint(x: right, y: eaves - height * 0.04))

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -line * 0.4), blur: line * 1.2, color: rgb(0x000000, 0.35))
    context.addPath(house)
    context.setStrokeColor(houseColor)
    context.setLineWidth(line)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    // Graph: a rising line with a dot on the latest value.
    let graphLeft = left + width * 0.27, graphRight = right - width * 0.31
    let graphBottom = bottom + height * 0.16, graphTop = bottom + height * 0.46
    let values: [CGFloat] = [0.15, 0.45, 0.30, 0.70, 0.55, 0.95]
    let graph = CGMutablePath()
    for (index, value) in values.enumerated() {
        let point = CGPoint(
            x: graphLeft + (graphRight - graphLeft) * CGFloat(index) / CGFloat(values.count - 1),
            y: graphBottom + (graphTop - graphBottom) * value
        )
        index == 0 ? graph.move(to: point) : graph.addLine(to: point)
    }
    context.saveGState()
    context.addPath(graph)
    context.setStrokeColor(graphColor)
    context.setLineWidth(line * 0.7)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    let last = graph.currentPoint
    let dot = line * 0.75
    context.setFillColor(graphColor)
    context.fillEllipse(in: CGRect(x: last.x - dot, y: last.y - dot, width: dot * 2, height: dot * 2))
    context.restoreGState()
}

func titleLine(_ text: String, size: CGFloat) -> CTLine {
    let font = NSFont.systemFont(ofSize: size, weight: .semibold)
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
    ]))
}

func drawTitle(_ context: CGContext, _ text: String, origin: CGPoint, size: CGFloat) {
    let line = titleLine(text, size: size)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.12, color: rgb(0x000000, 0.3))
    context.textPosition = origin
    CTLineDraw(line, context)
    context.restoreGState()
}

// MARK: - Output

func writePNG(_ context: CGContext, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

/// An opaque copy (no alpha channel); tvOS requires opaque back layers and Top Shelf images.
func writeOpaquePNG(_ context: CGContext, to url: URL) throws {
    let image = context.makeImage()!
    let opaque = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    opaque.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    try writePNG(opaque, to: url)
}

func writeJSON(_ object: Any, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]

/// Writes a layered image stack with the given base size at each scale.
func writeImageStack(name: String, width: Int, height: Int, scales: [Int]) throws {
    let stack = brandAssets.appendingPathComponent("\(name).imagestack")
    let layers = ["Front", "Middle", "Back"]
    try writeJSON(["info": info, "layers": layers.map { ["filename": "\($0).imagestacklayer"] }],
                  to: stack.appendingPathComponent("Contents.json"))

    for layer in layers {
        let layerURL = stack.appendingPathComponent("\(layer).imagestacklayer")
        try writeJSON(["info": info], to: layerURL.appendingPathComponent("Contents.json"))
        let imageset = layerURL.appendingPathComponent("Content.imageset")
        var images: [[String: Any]] = []

        for scale in scales {
            let size = CGSize(width: width * scale, height: height * scale)
            let context = makeContext(width: Int(size.width), height: Int(size.height))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let filename = "\(layer.lowercased())@\(scale)x.png"
            let url = imageset.appendingPathComponent(filename)
            switch layer {
            case "Back":
                drawBackground(context, size)
                try writeOpaquePNG(context, to: url)
            case "Middle":
                drawGlow(context, center: center, radius: size.height * 0.62)
                try writePNG(context, to: url)
            default:
                // Keep the house inside the safe area: edges are cropped during parallax.
                drawHouse(context, center: CGPoint(x: center.x, y: center.y + size.height * 0.02),
                          height: size.height * 0.56)
                try writePNG(context, to: url)
            }
            images.append(["idiom": "tv", "scale": "\(scale)x", "filename": filename])
        }
        try writeJSON(["images": images, "info": info], to: imageset.appendingPathComponent("Contents.json"))
    }
}

func writeTopShelf(name: String, width: Int, height: Int) throws {
    let imageset = brandAssets.appendingPathComponent("\(name).imageset")
    var images: [[String: Any]] = []
    for scale in [1, 2] {
        let size = CGSize(width: width * scale, height: height * scale)
        let context = makeContext(width: Int(size.width), height: Int(size.height))
        drawBackground(context, size)
        // tvOS shows the Top Shelf enlarged and cropped at the sides, so centre the
        // house and title as one group.
        let houseHeight = size.height * 0.42
        let titleSize = size.height * 0.14
        let gap = houseHeight * 0.3
        let titleWidth = CGFloat(CTLineGetTypographicBounds(titleLine("Home Assistant", size: titleSize), nil, nil, nil))
        let groupLeft = (size.width - (houseHeight + gap + titleWidth)) / 2
        let houseCenter = CGPoint(x: groupLeft + houseHeight / 2, y: size.height * 0.52)
        drawGlow(context, center: houseCenter, radius: size.height * 0.8)
        drawHouse(context, center: houseCenter, height: houseHeight)
        drawTitle(context, "Home Assistant",
                  origin: CGPoint(x: groupLeft + houseHeight + gap, y: size.height * 0.46),
                  size: titleSize)
        let filename = "\(name.lowercased().replacingOccurrences(of: " ", with: "-"))@\(scale)x.png"
        try writeOpaquePNG(context, to: imageset.appendingPathComponent(filename))
        images.append(["idiom": "tv", "scale": "\(scale)x", "filename": filename])
    }
    try writeJSON(["images": images, "info": info], to: imageset.appendingPathComponent("Contents.json"))
}

try? FileManager.default.removeItem(at: brandAssets)
try writeImageStack(name: "App Icon", width: 400, height: 240, scales: [1, 2])
try writeImageStack(name: "App Icon - App Store", width: 1280, height: 768, scales: [1])
try writeTopShelf(name: "Top Shelf Image", width: 1920, height: 720)
try writeTopShelf(name: "Top Shelf Image Wide", width: 2320, height: 720)
try writeJSON([
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
    "info": info,
], to: brandAssets.appendingPathComponent("Contents.json"))

print("Wrote \(brandAssets.path)")
