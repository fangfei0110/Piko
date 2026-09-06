import Foundation
import ImageIO

enum IconError: Error { case invalidArguments, invalidSource, compilationFailed, missingOutput }

guard CommandLine.arguments.count == 2 else { throw IconError.invalidArguments }
let output = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let icon = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("AppBundle/Assets/AppIcon.icon",isDirectory:true)
guard let source = CGImageSourceCreateWithURL(icon.appendingPathComponent("Assets/Piko.png") as CFURL,nil),
      let original = CGImageSourceCreateImageAtIndex(source,0,nil),
      original.width == original.height, original.width >= 1024,
      [CGImageAlphaInfo.none,.noneSkipFirst,.noneSkipLast].contains(original.alphaInfo) else {
    throw IconError.invalidSource
}
let manager = FileManager.default
let temporary = manager.temporaryDirectory.appendingPathComponent("Piko-Icon-\(UUID().uuidString)",isDirectory:true)
try manager.createDirectory(at:temporary,withIntermediateDirectories:true)
defer { try? manager.removeItem(at:temporary) }

// Ship the native icon stack as well as the legacy fallback, avoiding Tahoe's legacy-icon plate.
let process = Process()
process.executableURL = URL(fileURLWithPath:"/usr/bin/xcrun")
process.arguments = ["actool",icon.path,"--compile",temporary.path,
    "--output-format","human-readable-text","--notices","--warnings","--errors",
    "--output-partial-info-plist",temporary.appendingPathComponent("Info.plist").path,
    "--app-icon","AppIcon","--include-all-app-icons","--enable-on-demand-resources","NO",
    "--development-region","en","--target-device","mac",
    "--minimum-deployment-target","14.0","--platform","macosx"]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { throw IconError.compilationFailed }

try manager.createDirectory(at:output,withIntermediateDirectories:true)
for name in ["AppIcon.icns","Assets.car"] {
    let data = try Data(contentsOf:temporary.appendingPathComponent(name))
    guard !data.isEmpty else { throw IconError.missingOutput }
    try data.write(to:output.appendingPathComponent(name),options:.atomic)
}
