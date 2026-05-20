import AppKit
import CoreGraphics

/// Programmatic app icon — a stylized "long picture" with the centered
/// square thumbnail highlighted, evoking the WeChat Moments trick the app
/// exists to perform.
enum IconGenerator {
    static func makeIcon(size: CGFloat = 1024) -> NSImage? {
        let scale: CGFloat = 1
        let pxW = Int(size * scale)
        let pxH = Int(size * scale)
        guard let ctx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: size, height: size)
        ctx.scaleBy(x: scale, y: scale)

        // 1. Squircle background with a vertical gradient (macOS-style).
        let cornerRadius = size * 0.225
        let bgPath = CGPath(roundedRect: canvas, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.saveGState()
        ctx.addPath(bgPath); ctx.clip()
        let colors = [
            CGColor(red: 0.36, green: 0.55, blue: 0.98, alpha: 1.0),   // sky blue (top)
            CGColor(red: 0.55, green: 0.34, blue: 0.92, alpha: 1.0)    // violet  (bottom)
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),
                               end: CGPoint(x: 0, y: 0),
                               options: [])
        ctx.restoreGState()

        // 2. The "long picture" silhouette: a tall rounded rect with image bands.
        let stackW = size * 0.46
        let stackH = size * 0.78
        let stackX = (size - stackW) / 2
        let stackY = (size - stackH) / 2
        let stackRect = CGRect(x: stackX, y: stackY, width: stackW, height: stackH)
        let stackCorner = size * 0.045

        // Outer paper drop-shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                      blur: size * 0.04,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: stackRect, cornerWidth: stackCorner, cornerHeight: stackCorner, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()

        // Clip to the rounded paper for the bands.
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: stackRect, cornerWidth: stackCorner, cornerHeight: stackCorner, transform: nil))
        ctx.clip()

        // Five horizontal bands: top decoration, top image, CENTER SQUARE, bottom image, bottom decoration.
        let centerSide = stackW
        let centerY = stackY + (stackH - centerSide) / 2

        let topBandsH = centerY - stackY
        let band1H = topBandsH * 0.55
        let band1Y = stackY + (topBandsH - band1H) / 2 - topBandsH * 0.05
        let band0H = topBandsH * 0.22
        let band0Y = stackY + topBandsH * 0.02

        let botBandsH = stackY + stackH - (centerY + centerSide)
        let band3H = botBandsH * 0.55
        let band3Y = centerY + centerSide + (botBandsH - band3H) / 2 + botBandsH * 0.05
        let band4H = botBandsH * 0.22
        let band4Y = stackY + stackH - band4H - botBandsH * 0.02

        func fillBand(_ rect: CGRect, gradientFrom a: CGColor, to b: CGColor) {
            ctx.saveGState()
            ctx.addRect(rect); ctx.clip()
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [a, b] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: rect.minX, y: rect.maxY),
                                   end: CGPoint(x: rect.maxX, y: rect.minY),
                                   options: [])
            ctx.restoreGState()
        }

        // Soft gray accents (decorative thin bands)
        ctx.setFillColor(CGColor(red: 0.86, green: 0.88, blue: 0.93, alpha: 1.0))
        ctx.fill(CGRect(x: stackX, y: band0Y, width: stackW, height: band0H))
        ctx.fill(CGRect(x: stackX, y: band4Y, width: stackW, height: band4H))

        // Upper photo band — coral → orange
        fillBand(CGRect(x: stackX, y: band1Y, width: stackW, height: band1H),
                 gradientFrom: CGColor(red: 1.00, green: 0.55, blue: 0.42, alpha: 1.0),
                 to: CGColor(red: 0.96, green: 0.78, blue: 0.30, alpha: 1.0))

        // Lower photo band — teal → green
        fillBand(CGRect(x: stackX, y: band3Y, width: stackW, height: band3H),
                 gradientFrom: CGColor(red: 0.22, green: 0.78, blue: 0.65, alpha: 1.0),
                 to: CGColor(red: 0.36, green: 0.86, blue: 0.45, alpha: 1.0))

        // 3. THE CENTER SQUARE — this is the thumbnail. Make it pop.
        let centerRect = CGRect(x: stackX, y: centerY, width: centerSide, height: centerSide)
        // Inner photo: a stylized landscape (sky + sun + mountains).
        // Sky gradient
        ctx.saveGState()
        ctx.addRect(centerRect); ctx.clip()
        let skyTop = CGColor(red: 0.62, green: 0.84, blue: 1.00, alpha: 1.0)
        let skyBot = CGColor(red: 0.92, green: 0.97, blue: 1.00, alpha: 1.0)
        let skyG = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [skyTop, skyBot] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(skyG,
                               start: CGPoint(x: centerRect.midX, y: centerRect.maxY),
                               end: CGPoint(x: centerRect.midX, y: centerRect.midY),
                               options: [])
        // Sun
        let sunR = centerSide * 0.12
        let sunCenter = CGPoint(x: centerRect.minX + centerSide * 0.72,
                                y: centerRect.minY + centerSide * 0.70)
        ctx.setFillColor(CGColor(red: 1.00, green: 0.85, blue: 0.35, alpha: 1.0))
        ctx.fillEllipse(in: CGRect(x: sunCenter.x - sunR, y: sunCenter.y - sunR,
                                   width: sunR * 2, height: sunR * 2))
        // Far mountains
        ctx.setFillColor(CGColor(red: 0.52, green: 0.66, blue: 0.86, alpha: 1.0))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: centerRect.minX, y: centerRect.minY + centerSide * 0.55))
        ctx.addLine(to: CGPoint(x: centerRect.minX + centerSide * 0.25, y: centerRect.minY + centerSide * 0.32))
        ctx.addLine(to: CGPoint(x: centerRect.minX + centerSide * 0.55, y: centerRect.minY + centerSide * 0.55))
        ctx.addLine(to: CGPoint(x: centerRect.minX + centerSide * 0.78, y: centerRect.minY + centerSide * 0.40))
        ctx.addLine(to: CGPoint(x: centerRect.maxX, y: centerRect.minY + centerSide * 0.55))
        ctx.addLine(to: CGPoint(x: centerRect.maxX, y: centerRect.minY))
        ctx.addLine(to: CGPoint(x: centerRect.minX, y: centerRect.minY))
        ctx.closePath()
        ctx.fillPath()
        // Foreground hills
        ctx.setFillColor(CGColor(red: 0.27, green: 0.55, blue: 0.40, alpha: 1.0))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: centerRect.minX, y: centerRect.minY + centerSide * 0.30))
        ctx.addLine(to: CGPoint(x: centerRect.minX + centerSide * 0.30, y: centerRect.minY + centerSide * 0.10))
        ctx.addLine(to: CGPoint(x: centerRect.minX + centerSide * 0.60, y: centerRect.minY + centerSide * 0.32))
        ctx.addLine(to: CGPoint(x: centerRect.maxX, y: centerRect.minY + centerSide * 0.15))
        ctx.addLine(to: CGPoint(x: centerRect.maxX, y: centerRect.minY))
        ctx.addLine(to: CGPoint(x: centerRect.minX, y: centerRect.minY))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()

        // Crop guides — dashed yellow square outlining the thumbnail. This is
        // the visual "tell" of the whole app concept.
        ctx.saveGState()
        let outlineInset = size * 0.005
        let outline = centerRect.insetBy(dx: outlineInset, dy: outlineInset)
        ctx.setLineWidth(size * 0.018)
        ctx.setStrokeColor(CGColor(red: 1.00, green: 0.83, blue: 0.20, alpha: 1.0))
        ctx.setLineDash(phase: 0, lengths: [size * 0.045, size * 0.028])
        ctx.stroke(outline)
        ctx.restoreGState()

        // Restore from the stack clip so corner ticks can extend slightly.
        ctx.restoreGState()

        // 4. A subtle highlight stroke on the outer squircle to lift it.
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        ctx.setLineWidth(size * 0.012)
        ctx.addPath(CGPath(roundedRect: canvas.insetBy(dx: size * 0.006, dy: size * 0.006),
                           cornerWidth: cornerRadius - size * 0.006,
                           cornerHeight: cornerRadius - size * 0.006, transform: nil))
        ctx.strokePath()
        ctx.restoreGState()

        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}
