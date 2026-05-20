import Foundation
import CoreGraphics

/// Recommends which image to use as the WeChat thumbnail and how to split
/// the remaining images above/below it. The score blends two costs:
///
///   • paddingFraction = paddingPixels / composedHeight  (white space added
///     to center the thumbnail)
///   • cropLossFraction = 1 − min(w,h)/max(w,h)          (pixels discarded
///     when the thumbnail is center-cropped to a square)
///
/// score = (1 − cropWeight) · paddingFraction + cropWeight · cropLossFraction
/// cropWeight ∈ [0, 1].  0 = padding-only.  1 = cropping-only.
enum AutoArrange {
    struct Result {
        var orderedURLs: [URL]
        var thumbnailURL: URL
        var paddingPixels: Int
        var cropLossFraction: Double
        var paddingFraction: Double
        var score: Double
    }

    /// - Parameter fixedThumbnail: if non-nil, that image is forced to be the
    ///   thumbnail and only the above/below ordering is optimized.
    ///   `cropWeight` is then ignored.
    static func recommend(items: [ImageItem],
                          outputWidth W: Int,
                          cropWeight: Double,
                          fixedThumbnail: URL? = nil) -> Result? {
        guard items.count >= 1 else { return nil }

        struct Entry {
            let url: URL
            let h: Int            // scaled height at width W
            let cropLoss: Double  // 1 - min/max of original dimensions
        }
        var entries: [Entry] = []
        entries.reserveCapacity(items.count)
        for item in items {
            guard let cg = ImageProcessor.loadCGImage(url: item.url) else { continue }
            let w = max(1, cg.width)
            let hh = max(1, cg.height)
            let h = max(1, Int((Double(hh) / Double(w)) * Double(W)))
            let loss = 1.0 - Double(min(w, hh)) / Double(max(w, hh))
            entries.append(Entry(url: item.url, h: h, cropLoss: loss))
        }
        guard !entries.isEmpty else { return nil }

        if entries.count == 1 {
            return Result(orderedURLs: [entries[0].url],
                          thumbnailURL: entries[0].url,
                          paddingPixels: 0,
                          cropLossFraction: entries[0].cropLoss,
                          paddingFraction: 0,
                          score: cropWeight * entries[0].cropLoss)
        }

        let alpha = max(0.0, min(1.0, cropWeight))

        var best: (score: Double, thumbIdx: Int, aboveMask: [Bool],
                   padding: Int, padFrac: Double, cropLoss: Double)?

        // If a fixed thumbnail is supplied, restrict the candidate loop to that one.
        let candidateRange: [Int]
        if let fixed = fixedThumbnail, let fixedIdx = entries.firstIndex(where: { $0.url == fixed }) {
            candidateRange = [fixedIdx]
        } else {
            candidateRange = Array(entries.indices)
        }

        for t in candidateRange {
            var others: [(idx: Int, h: Int)] = []
            others.reserveCapacity(entries.count - 1)
            for j in entries.indices where j != t {
                others.append((j, entries[j].h))
            }
            let S = others.reduce(0) { $0 + $1.h }
            let cap = S

            // Boolean subset-sum DP, with chosen[] for reconstruction.
            var reachable = [Bool](repeating: false, count: cap + 1)
            reachable[0] = true
            var chosen = [Bool](repeating: false, count: others.count * (cap + 1))
            for (k, item) in others.enumerated() {
                let h = item.h
                if h > cap { continue }
                var s = cap
                while s >= h {
                    if !reachable[s] && reachable[s - h] {
                        reachable[s] = true
                        chosen[k * (cap + 1) + s] = true
                    }
                    s -= 1
                }
            }

            // Best subset sum, restricted to 2s ≥ S so that topSpace ≥ bottomSpace
            // and any required padding lands at the BOTTOM of the long pic, never
            // at the top. s = S is always reachable (all "others" go above), so a
            // valid choice always exists.
            var bestSum = S
            var bestDelta = Int.max
            for s in 0...cap {
                if !reachable[s] { continue }
                if 2 * s < S { continue }
                let d = 2 * s - S
                if d < bestDelta { bestDelta = d; bestSum = s }
            }

            let padding = bestDelta
            let composed = S + W + padding
            let padFrac = composed > 0 ? Double(padding) / Double(composed) : 0
            let cropLoss = entries[t].cropLoss
            let score = (1.0 - alpha) * padFrac + alpha * cropLoss

            if best == nil || score < best!.score {
                var aboveOriginal = [Bool](repeating: false, count: entries.count)
                var s = bestSum
                var k = others.count - 1
                while k >= 0 && s > 0 {
                    if chosen[k * (cap + 1) + s] {
                        aboveOriginal[others[k].idx] = true
                        s -= others[k].h
                    }
                    k -= 1
                }
                best = (score, t, aboveOriginal, padding, padFrac, cropLoss)
            }
        }

        guard let pick = best else { return nil }
        var above: [URL] = []
        var below: [URL] = []
        for j in entries.indices where j != pick.thumbIdx {
            if pick.aboveMask[j] { above.append(entries[j].url) }
            else                  { below.append(entries[j].url) }
        }
        let thumbURL = entries[pick.thumbIdx].url
        return Result(orderedURLs: above + [thumbURL] + below,
                      thumbnailURL: thumbURL,
                      paddingPixels: pick.padding,
                      cropLossFraction: pick.cropLoss,
                      paddingFraction: pick.padFrac,
                      score: pick.score)
    }
}
