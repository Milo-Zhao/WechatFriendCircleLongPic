import SwiftUI
import AppKit

/// Lets the user pick which square region of a non-square image becomes the
/// WeChat thumbnail. The chosen origin is stored on the ImageItem in
/// original-pixel coordinates with the top-left convention.
struct CropPickerView: View {
    @ObservedObject var item: ImageItem
    var onDone: () -> Void

    /// Current top-left of the crop square in original-pixel coords.
    @State private var origin: CGPoint = .zero
    /// Cached full-resolution NSImage (loaded once).
    @State private var image: NSImage?

    private var side: Int { item.squareSide }
    private var pw: CGFloat { CGFloat(item.pixelWidth) }
    private var ph: CGFloat { CGFloat(item.pixelHeight) }

    var body: some View {
        VStack(spacing: 12) {
            Text("Drag the square to choose what WeChat will show as the thumbnail")
                .font(.headline)
            Text("Image is \(item.pixelWidth) × \(item.pixelHeight). Crop is a \(side) × \(side) square.")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let maxBox = CGSize(width: geo.size.width, height: geo.size.height)
                let scale = min(maxBox.width / pw, maxBox.height / ph)
                let displayedW = pw * scale
                let displayedH = ph * scale
                let displayedSide = CGFloat(side) * scale
                let offsetX = (maxBox.width - displayedW) / 2
                let offsetY = (maxBox.height - displayedH) / 2

                ZStack(alignment: .topLeading) {
                    if let img = image {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.medium)
                            .frame(width: displayedW, height: displayedH)
                            .offset(x: offsetX, y: offsetY)
                    } else {
                        Color.gray.opacity(0.2)
                    }

                    // Dim everything outside the crop using mask cut-out.
                    Color.black.opacity(0.45)
                        .frame(width: displayedW, height: displayedH)
                        .offset(x: offsetX, y: offsetY)
                        .mask(
                            ZStack {
                                Rectangle().frame(width: displayedW, height: displayedH)
                                Rectangle()
                                    .frame(width: displayedSide, height: displayedSide)
                                    .offset(x: origin.x * scale, y: origin.y * scale)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                            .frame(width: displayedW, height: displayedH, alignment: .topLeading)
                        )
                        .allowsHitTesting(false)

                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: displayedSide, height: displayedSide)
                        .offset(x: offsetX + origin.x * scale,
                                y: offsetY + origin.y * scale)
                        .allowsHitTesting(false)

                    // Drag surface: any drag on the image area moves the crop.
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: displayedW, height: displayedH)
                        .offset(x: offsetX, y: offsetY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // Treat drag location as the desired CENTER of the crop.
                                    let localX = (value.location.x - offsetX) / scale
                                    let localY = (value.location.y - offsetY) / scale
                                    let half = CGFloat(side) / 2
                                    let nx = (localX - half).clamped(0, pw - CGFloat(side))
                                    let ny = (localY - half).clamped(0, ph - CGFloat(side))
                                    origin = CGPoint(x: nx, y: ny)
                                }
                        )
                }
                .frame(width: maxBox.width, height: maxBox.height)
            }
            .frame(minWidth: 420, minHeight: 320)

            HStack {
                Button("Reset to Center") {
                    origin = CGPoint(x: (pw - CGFloat(side)) / 2,
                                     y: (ph - CGFloat(side)) / 2)
                }
                Button("Use Center (clear custom crop)") {
                    item.customCropOrigin = nil
                    onDone()
                }
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    item.customCropOrigin = origin
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            image = NSImage(contentsOf: item.url)
            if let existing = item.customCropOrigin {
                origin = existing
            } else {
                origin = CGPoint(x: (pw - CGFloat(side)) / 2,
                                 y: (ph - CGFloat(side)) / 2)
            }
        }
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lo), Swift.max(lo, hi))
    }
}
