import AppKit
import Foundation

guard CommandLine.arguments.count == 2,
      let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      let icon = NSBitmapImageRep(data: data),
      icon.pixelsWide >= 60, icon.pixelsHigh == icon.pixelsWide,
      let middle = icon.colorAt(x: icon.pixelsWide / 2, y: icon.pixelsHigh / 2)?.usingColorSpace(.deviceRGB),
      let corner = icon.colorAt(x: icon.pixelsWide / 10, y: icon.pixelsHigh / 10)?.usingColorSpace(.deviceRGB),
      middle.redComponent > 0.88,
      middle.greenComponent > 0.37 && middle.greenComponent < 0.83,
      middle.blueComponent < 0.43,
      corner.redComponent > 0.92 && corner.greenComponent > 0.86 && corner.blueComponent > 0.7 else {
    fatalError("The compiled iPhone icon does not match the orange folder asset.")
}
print("Verified the compiled orange-folder iPhone icon (\(icon.pixelsWide)×\(icon.pixelsHigh)).")
