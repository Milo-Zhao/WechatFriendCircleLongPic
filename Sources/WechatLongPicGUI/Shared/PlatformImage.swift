import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#else
import AppKit
public typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    /// Build a PlatformImage from a CGImage in a way that works on both
    /// macOS (NSImage(cgImage:size:)) and iOS (UIImage(cgImage:)).
    static func from(cgImage cg: CGImage) -> PlatformImage {
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #endif
    }
}
