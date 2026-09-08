import AppKit

let W = 660.0, H = 400.0
let scale = 2.0   // @2x so the retina background is crisp

let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background: the app's pale pink, a touch warmer at the top.
let space = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: space, colors: [
  CGColor(colorSpace: space, components: [1.0, 0.957, 0.973, 1.0])!,
  CGColor(colorSpace: space, components: [1.0, 0.992, 0.996, 1.0])!,
] as CFArray, locations: [0.0, 1.0])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

// Arrow from the app icon towards the Applications folder.
let accent = NSColor(red: 0.957, green: 0.561, blue: 0.694, alpha: 1.0)
accent.setStroke()
accent.setFill()
let y = H - 210.0
let path = NSBezierPath()
path.lineWidth = 5
path.lineCapStyle = .round
path.move(to: NSPoint(x: 278, y: y))
path.line(to: NSPoint(x: 372, y: y))
path.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 396, y: y))
head.line(to: NSPoint(x: 368, y: y + 15))
head.line(to: NSPoint(x: 368, y: y - 15))
head.close()
head.fill()

// Two lines of instruction, Chinese above English.
func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
  let style = NSMutableParagraphStyle()
  style.alignment = .center
  let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size, weight: weight),
    .foregroundColor: NSColor(red: 0.42, green: 0.31, blue: 0.36, alpha: alpha),
    .paragraphStyle: style,
  ]
  NSString(string: text).draw(in: NSRect(x: 0, y: y, width: W, height: size * 1.6), withAttributes: attrs)
}
draw("把「番时」拖进 Applications", size: 17, weight: .semibold, alpha: 1.0, y: 74)
draw("Drag Anime Now into Applications", size: 13, weight: .regular, alpha: 0.62, y: 48)

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
