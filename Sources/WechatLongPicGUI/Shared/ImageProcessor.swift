import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

enum ImageProcessorError: Error {
    case noImages
    case noThumbnail
    case loadFailed(URL)
    case renderFailed
}

struct ImageProcessor {
    /// Compose a long picture from `items` (top → bottom in the given order),
    /// placing the item flagged as thumbnail as a centered W×W square so that
    /// WeChat Moments' auto-thumbnail crop will land on it.
    static func compose(items: [ImageItem], outputWidth: Int) throws -> CGImage {
        guard !items.isEmpty else { throw ImageProcessorError.noImages }
        guard let thumbIdx = items.firstIndex(where: { $0.isThumbnail }) else {
            throw ImageProcessorError.noThumbnail
        }

        let W = outputWidth
        var rescaledHeights: [Int] = []
        var cgImages: [CGImage] = []

        for (i, item) in items.enumerated() {
            guard let cg = loadCGImage(url: item.url) else {
                throw ImageProcessorError.loadFailed(item.url)
            }
            if i == thumbIdx {
                let square: CGImage
                if let origin = item.customCropOrigin {
                    square = customCropToSquare(cg, origin: origin)
                } else {
                    square = centerCropToSquare(cg)
                }
                let scaled = resize(square, width: W, height: W)
                cgImages.append(scaled)
                rescaledHeights.append(W)
            } else {
                let h = Int((Double(cg.height) / Double(cg.width)) * Double(W))
                let scaled = resize(cg, width: W, height: h)
                cgImages.append(scaled)
                rescaledHeights.append(h)
            }
        }

        // Compute Y position of each tile when stacked in order.
        var positions: [Int] = []
        var y = 0
        for h in rescaledHeights {
            positions.append(y)
            y += h
        }
        let stackedHeight = y                       // total height before padding
        let thumbY = positions[thumbIdx]            // top of thumbnail block
        let thumbCenter = thumbY + W / 2

        // Pad top or bottom so that thumbCenter == totalHeight/2.
        // Equivalently: top space (= thumbY + padTop) must equal bottom space (= stackedHeight - thumbY - W + padBot).
        // We add padding to whichever side is shorter.
        let topSpace = thumbY
        let bottomSpace = stackedHeight - thumbY - W
        var padTop = 0
        var padBot = 0
        if topSpace < bottomSpace {
            padTop = bottomSpace - topSpace
        } else {
            padBot = topSpace - bottomSpace
        }
        let totalHeight = stackedHeight + padTop + padBot
        // Sanity: (padTop + thumbY) + W/2 should equal totalHeight/2 (integer rounding tolerated).
        _ = thumbCenter

        guard let ctx = CGContext(
            data: nil,
            width: W,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageProcessorError.renderFailed }

        // Fill white background.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: totalHeight))

        // CoreGraphics origin is bottom-left; we want positions[] measured from top.
        for (i, img) in cgImages.enumerated() {
            let topY = positions[i] + padTop
            let h = rescaledHeights[i]
            let cgY = totalHeight - topY - h
            ctx.draw(img, in: CGRect(x: 0, y: cgY, width: W, height: h))
        }

        guard let out = ctx.makeImage() else { throw ImageProcessorError.renderFailed }
        return out
    }

    static func loadCGImage(url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary)
    }

    static func centerCropToSquare(_ img: CGImage) -> CGImage {
        let side = min(img.width, img.height)
        let x = (img.width - side) / 2
        let y = (img.height - side) / 2
        return img.cropping(to: CGRect(x: x, y: y, width: side, height: side)) ?? img
    }

    /// `origin` is in image-pixel coordinates with origin at the **top-left**
    /// (UI convention). CGImage cropping uses bottom-left, so we flip Y.
    static func customCropToSquare(_ img: CGImage, origin: CGPoint) -> CGImage {
        let side = min(img.width, img.height)
        let maxX = max(0, img.width - side)
        let maxY = max(0, img.height - side)
        let topLeftX = Int(origin.x.rounded()).clamped(to: 0...maxX)
        let topLeftY = Int(origin.y.rounded()).clamped(to: 0...maxY)
        let cgY = img.height - topLeftY - side
        return img.cropping(to: CGRect(x: topLeftX, y: cgY, width: side, height: side)) ?? img
    }

    static func resize(_ img: CGImage, width: Int, height: Int) -> CGImage {
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return img }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? img
    }

    static func writePNG(_ img: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageProcessorError.renderFailed
        }
        CGImageDestinationAddImage(dest, img, nil)
        if !CGImageDestinationFinalize(dest) {
            throw ImageProcessorError.renderFailed
        }
    }
}
