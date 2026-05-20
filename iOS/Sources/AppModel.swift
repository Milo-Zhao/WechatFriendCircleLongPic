import SwiftUI
import PhotosUI
import Photos
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [ImageItem] = []
    @Published var outputWidth: Int = 1080
    @Published var cropWeight: Double = 0.5
    @Published var userPickedThumbnail: Bool = false
    @Published var isWorking: Bool = false
    @Published var status: String?
    @Published var previewImage: UIImage?

    var hasThumbnail: Bool { items.contains(where: { $0.isThumbnail }) }

    // MARK: - Photo picker integration

    /// Load images selected via PhotosPicker into ImageItems. We write each
    /// picked photo to a temp file so the rest of the code (which assumes
    /// file URLs and CGImageSourceCreateWithURL) keeps working unchanged.
    func ingest(_ picks: [PhotosPickerItem]) async {
        isWorking = true
        defer { isWorking = false }
        for p in picks {
            guard let data = try? await p.loadTransferable(type: Data.self) else { continue }
            let ext = inferExtension(from: data) ?? "jpg"
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("longpic-\(UUID().uuidString).\(ext)")
            do {
                try data.write(to: tmp)
                items.append(ImageItem(url: tmp))
            } catch {
                status = "Failed to import a photo: \(error.localizedDescription)"
            }
        }
    }

    private func inferExtension(from data: Data) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let utRaw = CGImageSourceGetType(src) else { return nil }
        let ut = UTType(utRaw as String)
        return ut?.preferredFilenameExtension
    }

    // MARK: - Thumbnail star toggle

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

    // MARK: - Generation

    func generatePreview() {
        guard !items.isEmpty, hasThumbnail else { return }
        isWorking = true
        status = nil
        let snapshot = items
        let width = outputWidth
        Task.detached {
            do {
                let cg = try ImageProcessor.compose(items: snapshot, outputWidth: width)
                let img = UIImage(cgImage: cg)
                await MainActor.run {
                    self.previewImage = img
                    self.isWorking = false
                }
            } catch {
                await MainActor.run {
                    self.status = "\(error)"
                    self.isWorking = false
                }
            }
        }
    }

    func autoArrange() {
        guard !items.isEmpty else { return }
        isWorking = true
        status = nil
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
                self.status = "Auto-arranged (\(mode)) · padding ≈ \(r.paddingPixels) px (\(padPct)%) · crop ≈ \(cropPct)%"
                self.generatePreview()
            }
        }
    }

    // MARK: - Save to Photos

    func saveToPhotos() {
        guard !items.isEmpty, hasThumbnail else { return }
        isWorking = true
        let snapshot = items
        let width = outputWidth
        Task.detached {
            do {
                let cg = try ImageProcessor.compose(items: snapshot, outputWidth: width)
                let image = UIImage(cgImage: cg)
                try await self.requestPhotoAddPermission()
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                await MainActor.run {
                    self.status = "Saved to Photos."
                    self.isWorking = false
                }
            } catch {
                await MainActor.run {
                    self.status = "Save failed: \(error.localizedDescription)"
                    self.isWorking = false
                }
            }
        }
    }

    private func requestPhotoAddPermission() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited: return
        case .notDetermined:
            let new = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if new != .authorized && new != .limited {
                throw NSError(domain: "Photos", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo access denied"])
            }
        default:
            throw NSError(domain: "Photos", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo access denied — enable in Settings"])
        }
    }
}
