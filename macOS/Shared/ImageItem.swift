import Foundation
import CoreGraphics
import ImageIO

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

final class ImageItem: Identifiable, ObservableObject, Equatable {
    let id = UUID()
    /// Source URL. On iOS this is a temp file written by the PhotosPicker shim.
    let url: URL
    @Published var isThumbnail: Bool
    /// Top-left of the chosen square crop in original-image pixel coords (top-left origin).
    /// `nil` means "center-crop".
    @Published var customCropOrigin: CGPoint?
    let thumbnailPreview: PlatformImage?
    let pixelWidth: Int
    let pixelHeight: Int

    init(url: URL, isThumbnail: Bool = false) {
        self.url = url
        self.isThumbnail = isThumbnail
        self.thumbnailPreview = Self.makePreview(url: url)
        let dims = Self.pixelDims(url: url)
        self.pixelWidth = dims.w
        self.pixelHeight = dims.h
    }

    var squareSide: Int { max(1, min(pixelWidth, pixelHeight)) }
    var aspectRatio: Double { Double(pixelWidth) / Double(max(1, pixelHeight)) }
    var cropLoss: Double {
        let mn = Double(min(pixelWidth, pixelHeight))
        let mx = Double(max(pixelWidth, pixelHeight))
        return mx > 0 ? 1.0 - mn / mx : 0
    }

    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool { lhs.id == rhs.id }

    private static func pixelDims(url: URL) -> (w: Int, h: Int) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return (1, 1) }
        return (w, h)
    }

    private static func makePreview(url: URL) -> PlatformImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return PlatformImage.from(cgImage: cg)
    }
}
