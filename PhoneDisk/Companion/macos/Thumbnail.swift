import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let generator = AVAssetImageGenerator(asset: AVURLAsset(url: input))
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 360, height: 360)

do {
    let frame = try await generator.image(at: .zero).image
    guard let jpeg = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        exit(1)
    }
    CGImageDestinationAddImage(jpeg, frame, nil)
    exit(CGImageDestinationFinalize(jpeg) ? 0 : 1)
} catch {
    exit(1)
}
