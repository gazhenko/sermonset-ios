// Turns a picture into a one-ink mask for the website: white where the ink goes, transparent elsewhere.
// The page colors it with CSS `mask-image`, so one file works in light and dark themes.
//
//   swift tools/site/dither.swift in.jpg out.png --width 1600 --mode bayer|fs|dots --block 3
//       [--crop x,y,w,h (fractions)] [--contrast 1.4] [--brightness 0] [--gamma 1] [--ink dark|light]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

var args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { print("usage: dither in out [options]"); exit(1) }
let input = URL(fileURLWithPath: args.removeFirst()), output = URL(fileURLWithPath: args.removeFirst())
var options: [String: String] = [:]
while args.count >= 2 { options[args.removeFirst().replacingOccurrences(of: "--", with: "")] = args.removeFirst() }
let width = Int(options["width"] ?? "1600")!
let block = max(1, Int(options["block"] ?? "3")!)
let mode = options["mode"] ?? "bayer"
let contrast = Double(options["contrast"] ?? "1.3")!
let brightness = Double(options["brightness"] ?? "0")!
let gamma = Double(options["gamma"] ?? "1")!
let inkOnLight = options["ink"] == "light"

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("cannot read \(input.path)"); exit(1) }
if let crop = options["crop"]?.split(separator: ",").compactMap({ Double($0) }), crop.count == 4 {
    let w = Double(image.width), h = Double(image.height)
    image = image.cropping(to: CGRect(x: crop[0] * w, y: crop[1] * h, width: crop[2] * w, height: crop[3] * h))!
}
let height = Int(Double(width) * Double(image.height) / Double(image.width))

/// Luminance 0 (black) … 1 (white) at a given grid size.
func luminance(_ w: Int, _ h: Int) -> [Double] {
    var bytes = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return bytes.map { b in
        var l = Double(b) / 255
        l = (l - 0.5) * contrast + 0.5 + brightness
        l = pow(min(1, max(0, l)), gamma)
        return l
    }
}

var rgba = [UInt8](repeating: 0, count: width * height * 4)
func ink(_ x: Int, _ y: Int) { let i = (y * width + x) * 4; rgba[i] = 255; rgba[i + 1] = 255; rgba[i + 2] = 255; rgba[i + 3] = 255 }

if mode == "dots" {
    // Halftone: one dot per cell, area proportional to ink coverage, cells on a 45° screen.
    let cell = Double(block)
    let cols = Int(Double(width) / cell) + 4, rows = Int(Double(height) / cell) + 4
    let lw = max(1, width / block), lh = max(1, height / block)
    let lum = luminance(lw, lh)
    let ctx = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    let angle = Double.pi / 4
    for r in -rows...rows * 2 {
        for c in -cols...cols * 2 {
            let gx = Double(c) * cell, gy = Double(r) * cell
            let x = gx * cos(angle) - gy * sin(angle), y = gx * sin(angle) + gy * cos(angle)
            guard x >= -cell, y >= -cell, x < Double(width) + cell, y < Double(height) + cell else { continue }
            let sx = min(lw - 1, max(0, Int(x / Double(width) * Double(lw)))), sy = min(lh - 1, max(0, Int((Double(height) - y) / Double(height) * Double(lh))))
            let l = lum[sy * lw + sx]
            let coverage = inkOnLight ? l : 1 - l
            let radius = cell * 0.72 * sqrt(coverage)
            if radius > 0.35 { ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)) }
        }
    }
} else {
    let lw = max(1, width / block), lh = max(1, height / block)
    var lum = luminance(lw, lh)
    var on = [Bool](repeating: false, count: lw * lh)
    let bayer: [[Double]] = [[0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26], [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
                             [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25], [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]]
    for y in 0..<lh {
        for x in 0..<lw {
            let i = y * lw + x
            let value = inkOnLight ? lum[i] : 1 - lum[i]
            if mode == "fs" {
                let set = value > 0.5
                on[i] = set
                let error = value - (set ? 1 : 0)
                func spread(_ dx: Int, _ dy: Int, _ w: Double) {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < lw, ny < lh else { return }
                    let j = ny * lw + nx
                    lum[j] += inkOnLight ? error * w : -error * w
                }
                spread(1, 0, 7 / 16); spread(-1, 1, 3 / 16); spread(0, 1, 5 / 16); spread(1, 1, 1 / 16)
            } else {
                on[i] = value > (bayer[y % 8][x % 8] + 0.5) / 64
            }
        }
    }
    // Rows come out top-down from the grayscale context.
    for y in 0..<height {
        for x in 0..<width {
            let sx = min(lw - 1, x / block), sy = min(lh - 1, y / block)
            if on[sy * lw + sx] { ink(x, y) }
        }
    }
}

let ctx = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let result = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, result, nil)
CGImageDestinationFinalize(dest)
print("wrote \(output.lastPathComponent) \(width)×\(height)")
