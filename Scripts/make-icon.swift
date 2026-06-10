import AppKit

// Renders the app icon: a green pixel "crab" Space Invader on a near-black rounded
// square, then emits a 1024×1024 PNG. Run with Homebrew swift; pipe through sips +
// iconutil (see make-icon.sh) to produce AppIcon.icns.

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded-square plate, inset so it matches other Dock icons' visual weight.
let inset: CGFloat = 96
let plate = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
let radius = plate.width * 0.225
let platePath = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Dark vertical gradient fill.
ctx.saveGState()
ctx.addPath(platePath); ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: space,
                      colors: [CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1),
                               CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// Hairline highlight border.
ctx.addPath(platePath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
ctx.setLineWidth(4)
ctx.strokePath()

// The crab (11×8), centred, ~62% of the plate width.
let crab = [
    "..X.....X..", "...X...X...", "..XXXXXXX..", ".XX.XXX.XX.",
    "XXXXXXXXXXX", "X.XXXXXXX.X", "X.X.....X.X", "...XX.XX...",
]
let cols: CGFloat = 11, rows: CGFloat = 8
let cell = (plate.width * 0.62 / cols).rounded()
let gw = cell * cols, gh = cell * rows
let ox = (size - gw) / 2, oy = (size - gh) / 2

let crabPath = CGMutablePath()
for (r, line) in crab.enumerated() {
    for (c, ch) in line.enumerated() where ch != "." {
        let x = ox + CGFloat(c) * cell
        let y = oy + (rows - 1 - CGFloat(r)) * cell   // flip: row 0 is the top
        crabPath.addRect(CGRect(x: x, y: y, width: cell, height: cell))
    }
}
ctx.setShadow(offset: .zero, blur: 26, color: CGColor(red: 0.30, green: 1.0, blue: 0.55, alpha: 0.55))
ctx.setFillColor(CGColor(red: 0.30, green: 1.0, blue: 0.55, alpha: 1))
ctx.addPath(crabPath)
ctx.fillPath()

img.unlockFocus()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
