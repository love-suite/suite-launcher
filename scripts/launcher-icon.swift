// Draws Launcher's icon: a blue rounded rect with a white square.grid.3x3.fill symbol.
// Compiled and run at build time:
//   swiftc -O -o build/launcher-icon scripts/launcher-icon.swift && build/launcher-icon <output.icns>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "build/LauncherIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Launcher-\(getpid()).iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (side, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                     (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
                     (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    let s = CGFloat(side)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSColor(calibratedRed: 0.18, green: 0.46, blue: 0.96, alpha: 1.0).setFill()
    path.fill()
    let symSize = s * 0.62
    let symRect = CGRect(x: (s - symSize) / 2, y: (s - symSize) / 2, width: symSize, height: symSize)
    let config = NSImage.SymbolConfiguration(paletteColors: [.white])
        .applying(NSImage.SymbolConfiguration(pointSize: symSize * 0.72, weight: .medium))
    if let sym = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        sym.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent("icon_\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
