import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [ImageItem] = []
    @Published var outputWidth: Int = 1080
    @Published var cropWeight: Double = 0.5
    /// True once the user has starred a thumbnail themselves; keeps it fixed during Auto Arrange.
    @Published var userPickedThumbnail: Bool = false
    @Published var isWorking: Bool = false
    @Published var lastError: String?
    @Published var previewImage: NSImage?

    var hasThumbnail: Bool { items.contains(where: { $0.isThumbnail }) }

    func addURLs(_ urls: [URL]) {
        let supported: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]
        for u in urls where supported.contains(u.pathExtension.lowercased()) {
            items.append(ImageItem(url: u))
        }
    }

    func setThumbnail(_ item: ImageItem) {
        if item.isThumbnail {
            item.isThumbnail = false
            userPickedThumbnail = false
        } else {
            for it in items { it.isThumbnail = (it.id == item.id) }
            userPickedThumbnail = true
        }
        objectWillChange.send()
    }

    func remove(at offsets: IndexSet) {
        let removingThumb = offsets.contains { items[$0].isThumbnail }
        items.remove(atOffsets: offsets)
        if removingThumb { userPickedThumbnail = false }
    }

    func move(from src: IndexSet, to dst: Int) {
        items.move(fromOffsets: src, toOffset: dst)
    }

    func autoArrange() {
        guard !items.isEmpty else { return }
        isWorking = true
        lastError = nil
        let snapshot = items
        let width = outputWidth
        let weight = cropWeight
        let fixed: URL? = userPickedThumbnail
            ? snapshot.first(where: { $0.isThumbnail })?.url
            : nil
        Task.detached {
            let result = AutoArrange.recommend(items: snapshot,
                                               outputWidth: width,
                                               cropWeight: weight,
                                               fixedThumbnail: fixed)
            await MainActor.run {
                guard let r = result else { self.isWorking = false; return }
                let byURL = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.url, $0) })
                let reordered = r.orderedURLs.compactMap { byURL[$0] }
                for it in reordered { it.isThumbnail = (it.url == r.thumbnailURL) }
                self.items = reordered
                let padPct = Int((r.paddingFraction * 100).rounded())
                let cropPct = Int((r.cropLossFraction * 100).rounded())
                let mode = fixed == nil ? "picked thumbnail + order" : "kept your thumbnail, reordered"
                self.lastError = "Auto-arranged (\(mode)) · padding ≈ \(r.paddingPixels) px (\(padPct)%) · thumbnail crop ≈ \(cropPct)%"
                self.generatePreview()
            }
        }
    }

    func generatePreview() {
        guard !items.isEmpty else { return }
        isWorking = true
        lastError = nil
        let snapshot = items
        let width = outputWidth
        Task.detached {
            do {
                let cg = try ImageProcessor.compose(items: snapshot, outputWidth: width)
                let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                await MainActor.run {
                    self.previewImage = img
                    self.isWorking = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = "\(error)"
                    self.isWorking = false
                }
            }
        }
    }

    func export() {
        guard !items.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "wechat_long_pic.png"
        panel.begin { [weak self] resp in
            guard let self, resp == .OK, let url = panel.url else { return }
            self.isWorking = true
            let snapshot = self.items
            let width = self.outputWidth
            Task.detached {
                do {
                    let cg = try ImageProcessor.compose(items: snapshot, outputWidth: width)
                    try ImageProcessor.writePNG(cg, to: url)
                    await MainActor.run { self.isWorking = false }
                } catch {
                    await MainActor.run {
                        self.lastError = "\(error)"
                        self.isWorking = false
                    }
                }
            }
        }
    }
}
