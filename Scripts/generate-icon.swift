import AppKit

let output = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath:output).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let image = NSImage(size:NSSize(width:pixels,height:pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x:CGFloat(pixels)/1024,y:CGFloat(pixels)/1024)
        let bounds = CGRect(x:72,y:72,width:880,height:880)
        let shape = CGPath(roundedRect:bounds,cornerWidth:196,cornerHeight:196,transform:nil)
        context.setFillColor(NSColor(srgbRed:0.0596,green:0.4321,blue:0.3179,alpha:1).cgColor)
        context.addPath(shape); context.fillPath()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.13).cgColor)
        context.setLineWidth(3)
        context.addPath(CGPath(roundedRect:bounds.insetBy(dx:22,dy:22),cornerWidth:176,cornerHeight:176,transform:nil)); context.strokePath()
        let pulse = CGMutablePath()
        pulse.move(to:CGPoint(x:218,y:486)); pulse.addLine(to:CGPoint(x:362,y:486))
        pulse.addLine(to:CGPoint(x:429,y:647)); pulse.addLine(to:CGPoint(x:519,y:343))
        pulse.addLine(to:CGPoint(x:610,y:560)); pulse.addLine(to:CGPoint(x:675,y:486)); pulse.addLine(to:CGPoint(x:806,y:486))
        context.addPath(pulse); context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(43); context.setLineCap(.round); context.setLineJoin(.round); context.strokePath()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:iconset.appendingPathComponent(filename))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath:"/usr/bin/iconutil")
process.arguments = ["-c","icns",iconset.path,"-o",URL(fileURLWithPath:output).appendingPathComponent("AppIcon.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("Icon generation failed") }
try FileManager.default.removeItem(at:iconset)
