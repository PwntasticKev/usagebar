// Renders the UsageBar app icon (two usage bars on a dark tile) to a 1024px PNG.
// Usage: swift make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset: CGFloat = 100
let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
NSColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()

func bar(y: CGFloat, fill: CGFloat, color: NSColor) {
    let height: CGFloat = 110
    let track = NSRect(x: 230, y: y, width: 564, height: height)
    NSColor(white: 1, alpha: 0.12).setFill()
    NSBezierPath(roundedRect: track, xRadius: height / 2, yRadius: height / 2).fill()
    color.setFill()
    let filled = NSRect(x: track.minX, y: y, width: track.width * fill, height: height)
    NSBezierPath(roundedRect: filled, xRadius: height / 2, yRadius: height / 2).fill()
}

bar(y: 560, fill: 0.35, color: NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1))
bar(y: 354, fill: 0.85, color: NSColor(red: 0.36, green: 0.78, blue: 0.62, alpha: 1))

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write("failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
