import Foundation
import UIKit
import XCTest

@MainActor
func renderingJSONString(_ value: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: [value]), encoding: .utf8)!.dropFirst().dropLast().description
}

@MainActor
func renderingAverageRGB(_ source: String) throws -> [UInt8] {
    let encoded = try XCTUnwrap(source.split(separator: ",", maxSplits: 1).last)
    let bytes = try XCTUnwrap(Data(base64Encoded: String(encoded)))
    let image = try XCTUnwrap(UIImage(data: bytes)?.cgImage)
    var pixel: [UInt8] = [0, 0, 0, 0]
    try pixel.withUnsafeMutableBytes { buffer in
        let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return pixel
}
