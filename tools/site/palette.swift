// Prints a picture in a few flat inks with a 4×4 ordered (Bayer) dither, one pixel per cell.
// The page scales it up with `image-rendering: pixelated`, so the cells stay square and crisp.
//
//   swift tools/site/palette.swift in.jpg out.png --width 520 --inks 1B1640,4A1FF2,F0B92E,F4F4F1
//       [--spread 0.45] [--contrast 1.15] [--crop x,y,w,h (fractions)]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

var args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { print("usage: palette in out [options]"); exit(1) }
let input = URL(fileURLWithPath: args.removeFirst()), output = URL(fileURLWithPath: args.removeFirst())
var options: [String: String] = [:]
while args.count >= 2 { options[args.removeFirst().replacingOccurrences(of: "--", with: "")] = args.removeFirst() }
let width = Int(options["width"] ?? "520")!
let spread = Double(options["spread"] ?? "0.45")!
let contrast = Double(options["contrast"] ?? "1.15")!
let inks: [(Double, Double, Double)] = (options["inks"] ?? "1B1640,4A1FF2,F0B92E,F4F4F1").split(separator: ",").map { hex in
    let v = Int(hex, radix: 16)!
    return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("cannot read \(input.path)"); exit(1) }
if let crop = options["crop"]?.split(separator: ",").compactMap({ Double($0) }), crop.count == 4 {
    let w = Double(image.width), h = Double(image.height)
    image = image.cropping(to: CGRect(x: crop[0] * w, y: crop[1] * h, width: crop[2] * w, height: crop[3] * h))!
}
let height = Int(Double(width) * Double(image.height) / Double(image.width))

let space = CGColorSpace(name: CGColorSpace.sRGB)!
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        let t = ((bayer[(y % 4) * 4 + x % 4] + 0.5) / 16 - 0.5) * spread
        func channel(_ k: Int) -> Double { min(1, max(0, (Double(pixels[i + k]) / 255 - 0.5) * contrast + 0.5 + t)) }
        let r = channel(0), g = channel(1), b = channel(2)
        var best = 0, bestDistance = Double.infinity
        for (n, ink) in inks.enumerated() {
            let dr = r - ink.0, dg = g - ink.1, db = b - ink.2
            let distance = 0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db
            if distance < bestDistance { bestDistance = distance; best = n }
        }
        pixels[i] = UInt8(inks[best].0 * 255); pixels[i + 1] = UInt8(inks[best].1 * 255); pixels[i + 2] = UInt8(inks[best].2 * 255); pixels[i + 3] = 255
    }
}

let result = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, result, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output.path) \(width)×\(height)")
