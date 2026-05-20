import SwiftUI

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
                RoundedRectangle(cornerRadius: 6)
                    .fill(.gray.opacity(0.3))
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
