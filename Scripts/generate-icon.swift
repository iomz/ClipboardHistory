import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Master pixels remain untouched. Only required representation resizing and
// explicit sRGB output tagging happen here; no masking or alpha thresholding.
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: generate-icon.swift master.png output.iconset") }
let sourceURL = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2], isDirectory: true)
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == image.height, image.width >= 1024,
      [.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo) else {
    fatalError("Master must be square, at least 1024 pixels, and have alpha")
}
// Approved untagged master is interpreted as sRGB, not monitor/device RGB.
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let taggedImage = image.copy(colorSpace: sRGB)!
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
for (name, size) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
] {
    let context = CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: sRGB,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(taggedImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    let path = output.appendingPathComponent(name).appendingPathExtension("png")
    let destination = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(path.path)") }
}
