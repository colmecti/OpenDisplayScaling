// SPDX-License-Identifier: MIT
// Original vector artwork. No fonts or third-party image assets are bundled.
import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size)/1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let base = NSBezierPath(roundedRect: NSRect(x:64,y:64,width:896,height:896),xRadius:200,yRadius:200)
    NSColor(calibratedRed:0.045,green:0.075,blue:0.15,alpha:1).setFill(); base.fill()
    let screen = NSBezierPath(roundedRect:NSRect(x:190,y:285,width:644,height:448),xRadius:48,yRadius:48)
    NSColor(calibratedRed:0.35,green:0.72,blue:1,alpha:1).setStroke(); screen.lineWidth=30; screen.stroke()
    let inner = NSBezierPath(roundedRect:NSRect(x:290,y:380,width:352,height:252),xRadius:20,yRadius:20)
    NSColor(calibratedRed:0.12,green:0.85,blue:0.74,alpha:1).setStroke(); inner.lineWidth=22; inner.stroke()
    let arrow = NSBezierPath(); arrow.move(to:NSPoint(x:580,y:566)); arrow.line(to:NSPoint(x:722,y:670))
    arrow.move(to:NSPoint(x:655,y:670)); arrow.line(to:NSPoint(x:722,y:670)); arrow.line(to:NSPoint(x:722,y:603))
    arrow.lineWidth=28; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSColor.white.setStroke(); arrow.stroke()
    let stand=NSBezierPath(); stand.move(to:NSPoint(x:512,y:275)); stand.line(to:NSPoint(x:512,y:210))
    stand.move(to:NSPoint(x:396,y:210)); stand.line(to:NSPoint(x:628,y:210))
    stand.lineWidth=30; stand.lineCapStyle = .round
    NSColor(calibratedRed:0.35,green:0.72,blue:1,alpha:1).setStroke(); stand.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512] {
    try render(size).write(to:directory.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size*2).write(to:directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
