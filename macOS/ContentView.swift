import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
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
