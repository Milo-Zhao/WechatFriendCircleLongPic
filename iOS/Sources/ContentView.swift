import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject var model = AppModel()
    @State private var picks: [PhotosPickerItem] = []
    @State private var editMode: EditMode = .inactive
    @State private var showingPreview = false

    var body: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                emptyState
            } else {
                imageList
            }
            controls
        }
        .navigationTitle("WeChat Long Pic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !model.items.isEmpty {
                    EditButton().environment(\.editMode, $editMode)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                PhotosPicker(selection: $picks, matching: .images, photoLibrary: .shared()) {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .onChange(of: picks) { _, newValue in
            guard !newValue.isEmpty else { return }
            let copy = newValue
            picks = []
            Task { await model.ingest(copy) }
        }
        .sheet(isPresented: $showingPreview) { previewSheet }
        .environment(\.editMode, $editMode)
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Tap + to add photos.\nStar one as the WeChat thumbnail,\nor use Auto Arrange to let the app pick.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
        }
    }

    var imageList: some View {
        List {
            ForEach(model.items) { item in
                ImageRow(item: item, model: model)
            }
            .onMove { src, dst in model.move(from: src, to: dst) }
            .onDelete { idx in model.remove(at: idx) }
        }
        .listStyle(.plain)
    }

    var controls: some View {
        VStack(spacing: 10) {
            if model.items.count > 0 {
                HStack {
                    Text("Less padding").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $model.cropWeight, in: 0...1)
                    Text("Less cropping").font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Width")
                    TextField("", value: $model.outputWidth, format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                    Text("px").foregroundStyle(.secondary)
                    Spacer()
                }
            }
            HStack {
                Button {
                    model.autoArrange()
                } label: {
                    Label("Auto Arrange", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .disabled(model.items.isEmpty || model.isWorking)

                Button {
                    model.generatePreview()
                    showingPreview = true
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .buttonStyle(.bordered)
                .disabled(model.items.isEmpty || model.isWorking || !model.hasThumbnail)

                Spacer()

                Button {
                    model.saveToPhotos()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.items.isEmpty || model.isWorking || !model.hasThumbnail)
            }
            if let s = model.status {
                Text(s).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.isWorking {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(12)
        .background(.bar)
    }

    var previewSheet: some View {
        NavigationStack {
            ScrollView {
                if let img = model.previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay(GeometryReader { geo in
                            // Red dashed square at the geometric center — what WeChat will crop.
                            let side = geo.size.width
                            Rectangle()
                                .stroke(Color.red.opacity(0.85),
                                        style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                .frame(width: side, height: side)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                .allowsHitTesting(false)
                        })
                } else if model.isWorking {
                    ProgressView().padding(50)
                } else {
                    Text("No preview yet").foregroundStyle(.secondary).padding(50)
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingPreview = false }
                }
            }
        }
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
                    .font(.title3)
            }
            .buttonStyle(.plain)

            if let preview = item.thumbnailPreview {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipped()
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.3))
                    .frame(width: 56, height: 56)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                    .font(.subheadline)
                Text("\(item.pixelWidth) × \(item.pixelHeight)")
                    .font(.caption2).foregroundStyle(.secondary)
                if item.isThumbnail {
                    HStack(spacing: 4) {
                        Text("Thumbnail · crop \(cropLossPct)%")
                            .font(.caption2).foregroundStyle(.secondary)
                        if item.customCropOrigin != nil {
                            Text("(custom)").font(.caption2).foregroundStyle(.blue)
                        }
                    }
                }
            }
            Spacer()
            if item.isThumbnail && isNonSquare {
                Button {
                    showingCropper = true
                } label: {
                    Image(systemName: "crop").font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingCropper) {
            CropPickerView(item: item) {
                showingCropper = false
                if model.previewImage != nil { model.generatePreview() }
            }
        }
    }
}
