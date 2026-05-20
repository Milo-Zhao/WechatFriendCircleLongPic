import SwiftUI
import AppKit

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
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 48, height: 48)
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
                if model.previewImage != nil { model.generatePreview() }
            }
        }
    }
}
