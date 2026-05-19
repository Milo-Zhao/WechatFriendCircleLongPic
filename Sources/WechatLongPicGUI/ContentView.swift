import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class AppModel: ObservableObject {
    @Published var items: [ImageItem] = []
    @Published var outputWidth: Int = 1080
    @Published var cropWeight: Double = 0.5
    /// True once the user has clicked the ☆ star themselves. Auto-arrange
    /// keeps a user-chosen thumbnail fixed; otherwise it picks one too.
    @Published var userPickedThumbnail: Bool = false
    @Published var isWorking: Bool = false
    @Published var lastError: String?
    @Published var previewImage: NSImage?

    func addURLs(_ urls: [URL]) {
        let supported: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]
        for u in urls where supported.contains(u.pathExtension.lowercased()) {
            items.append(ImageItem(url: u))
        }
        // Intentionally no default thumbnail. The user either stars one
        // themselves, or hits Auto Arrange in free mode and the algorithm picks one.
    }

    func setThumbnail(_ item: ImageItem) {
        // Toggle: clicking the already-starred row clears the thumbnail and
        // rolls back to the "no thumbnail" state, so a subsequent Auto Arrange
        // runs in free mode (picks thumbnail AND order).
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

    var hasThumbnail: Bool { items.contains(where: { $0.isThumbnail }) }

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
        // Mode A: user has starred a thumbnail → keep it fixed, optimize order only.
        // Mode B: user has not picked one → let the algorithm choose both.
        let fixed: URL? = userPickedThumbnail
            ? snapshot.first(where: { $0.isThumbnail })?.url
            : nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AutoArrange.recommend(items: snapshot,
                                               outputWidth: width,
                                               cropWeight: weight,
                                               fixedThumbnail: fixed)
            DispatchQueue.main.async {
                guard let r = result else { self.isWorking = false; return }
                let byURL = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.url, $0) })
                let reordered = r.orderedURLs.compactMap { byURL[$0] }
                for it in reordered { it.isThumbnail = (it.url == r.thumbnailURL) }
                self.items = reordered
                let padPct = Int((r.paddingFraction * 100).rounded())
                let cropPct = Int((r.cropLossFraction * 100).rounded())
                let mode = fixed == nil ? "picked thumbnail + order" : "kept your thumbnail, reordered"
                self.lastError = "Auto-arranged (\(mode)) · padding ≈ \(r.paddingPixels) px (\(padPct)%) · thumbnail crop ≈ \(cropPct)%"
                // Regenerate the preview with the new arrangement.
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
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let cg = try ImageProcessor.compose(items: snapshot, outputWidth: width)
                let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                DispatchQueue.main.async {
                    self.previewImage = img
                    self.isWorking = false
                }
            } catch {
                DispatchQueue.main.async {
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
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            self.isWorking = true
            let snapshot = self.items
            let width = self.outputWidth
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let cg = try ImageProcessor.compose(items: snapshot, outputWidth: width)
                    try ImageProcessor.writePNG(cg, to: url)
                    DispatchQueue.main.async { self.isWorking = false }
                } catch {
                    DispatchQueue.main.async {
                        self.lastError = "\(error)"
                        self.isWorking = false
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject var model = AppModel()

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 360, idealWidth: 420)
            rightPane
                .frame(minWidth: 360)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    var leftPane: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    pickFiles()
                } label: {
                    Label("Add Images…", systemImage: "plus")
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("Width")
                    TextField("", value: $model.outputWidth, formatter: NumberFormatter())
                        .frame(width: 70)
                    Text("px")
                }
            }
            .padding(10)

            List {
                ForEach(model.items) { item in
                    ImageRow(item: item, model: model)
                }
                .onMove { src, dst in model.move(from: src, to: dst) }
                .onDelete { idx in model.remove(at: idx) }
            }
            .listStyle(.inset)
            .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)

            Divider()

            VStack(spacing: 6) {
                HStack {
                    Text("Prefer less padding")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $model.cropWeight, in: 0...1)
                    Text("Prefer less cropping")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Auto Arrange") { model.autoArrange() }
                        .disabled(model.items.isEmpty || model.isWorking)
                        .help("Pick the thumbnail and ordering that minimize the weighted blend of padding and crop loss")
                    Button("Preview") { model.generatePreview() }
                        .disabled(model.items.isEmpty || model.isWorking || !model.hasThumbnail)
                        .help(model.hasThumbnail ? "" : "Star a thumbnail row, or run Auto Arrange")
                    Spacer()
                    Button("Export Long Pic…") { model.export() }
                        .disabled(model.items.isEmpty || model.isWorking || !model.hasThumbnail)
                        .keyboardShortcut("e")
                }
            }
            .padding(10)

            if let err = model.lastError {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal, 10).padding(.bottom, 8)
            }
        }
    }

    var rightPane: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            if model.isWorking {
                ProgressView()
            } else if let img = model.previewImage {
                ScrollView {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay(centerCropOverlay(for: img), alignment: .center)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Drag images in. Star (☆) one row as the thumbnail and Preview,\nor hit Auto Arrange to let the algorithm pick.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    func centerCropOverlay(for img: NSImage) -> some View {
        GeometryReader { geo in
            let displayedW = geo.size.width
            let scale = displayedW / img.size.width
            let displayedH = img.size.height * scale
            let squareSide = displayedW
            let centerY = displayedH / 2
            Rectangle()
                .stroke(Color.red.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(width: squareSide, height: squareSide)
                .position(x: displayedW / 2, y: centerY)
                .allowsHitTesting(false)
        }
    }

    func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.allowedContentTypes = [.image]
        if p.runModal() == .OK {
            model.addURLs(p.urls)
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let u = url { urls.append(u) }
                group.leave()
            }
        }
        group.notify(queue: .main) { self.model.addURLs(urls) }
        return true
    }
}

struct ImageRow: View {
    @ObservedObject var item: ImageItem
    @ObservedObject var model: AppModel
    @State private var showingCropper = false

    private var cropLossPct: Int { Int((item.cropLoss * 100).rounded()) }
    private var isNonSquare: Bool { item.pixelWidth != item.pixelHeight }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.setThumbnail(item)
            } label: {
                Image(systemName: item.isThumbnail ? "star.fill" : "star")
                    .foregroundStyle(item.isThumbnail ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help("Use as WeChat thumbnail")

            if let preview = item.thumbnailPreview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 48, height: 48).cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                if item.isThumbnail {
                    HStack(spacing: 4) {
                        Text("WeChat thumbnail · crop \(cropLossPct)%")
                            .font(.caption).foregroundStyle(.secondary)
                        if item.customCropOrigin != nil {
                            Text("(custom)").font(.caption).foregroundStyle(.blue)
                        }
                    }
                }
            }
            Spacer()

            if item.isThumbnail && isNonSquare {
                Button("Crop…") { showingCropper = true }
                    .controlSize(.small)
                    .help("Choose which square region becomes the WeChat thumbnail")
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showingCropper) {
            CropPickerView(item: item) {
                showingCropper = false
                // Regenerate preview so the new crop is visible immediately.
                if model.previewImage != nil { model.generatePreview() }
            }
        }
    }
}
