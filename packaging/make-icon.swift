import AppKit

// Crops a source image to a square and writes a full macOS .iconset.
// usage: swift make-icon.swift <src.png> <out.iconset> [left|center|right]
let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: make-icon.swift <src.png> <out.iconset> [left|center|right]") }
let srcPath = args[1]
let outDir = args[2]
let anchor = args.count >= 4 ? args[3] : "center"

guard let rep = NSImage(contentsOfFile: srcPath).flatMap({ $0.tiffRepresentation }).flatMap({ NSBitmapImageRep(data: $0) }),
      let cg = rep.cgImage else { fatalError("cannot load \(srcPath)") }

let side = min(cg.width, cg.height)
let maxX = cg.width - side
let originX: Int
switch anchor {
case "left":  originX = 0          // keep the left, crop the right
case "right": originX = maxX
default:      originX = maxX / 2
}
guard let square = cg.cropping(to: CGRect(x: originX, y: 0, width: side, height: side)) else {
    fatalError("crop failed")
}

let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try! fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func emit(_ size: Int, _ name: String) {
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.interpolationQuality = .high
    ctx.draw(square, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let out = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { return }
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),   (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),   (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]
sizes.forEach { emit($0.0, $0.1) }
print("wrote \(sizes.count) sizes (\(anchor) crop) → \(outDir)")
