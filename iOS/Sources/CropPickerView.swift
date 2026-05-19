import SwiftUI
import UIKit

struct CropPickerView: View {
    @ObservedObject var item: ImageItem
    var onDone: () -> Void

    @State private var origin: CGPoint = .zero
    @State private var image: UIImage?

    private var side: Int { item.squareSide }
    private var pw: CGFloat { CGFloat(item.pixelWidth) }
    private var ph: CGFloat { CGFloat(item.pixelHeight) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Drag inside the photo to choose which square WeChat will use.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                GeometryReader { geo in
                    let maxBox = geo.size
                    let scale = min(maxBox.width / pw, maxBox.height / ph)
                    let displayedW = pw * scale
                    let displayedH = ph * scale
                    let displayedSide = CGFloat(side) * scale
                    let offsetX = (maxBox.width - displayedW) / 2
                    let offsetY = (maxBox.height - displayedH) / 2

                    ZStack(alignment: .topLeading) {
                        if let img = image {
                            Image(uiImage: img)
                                .resizable()
                                .interpolation(.medium)
                                .frame(width: displayedW, height: displayedH)
                                .offset(x: offsetX, y: offsetY)
                        } else {
                            Color.gray.opacity(0.15)
                        }

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
                            .offset(x: offsetX + origin.x * scale, y: offsetY + origin.y * scale)
                            .allowsHitTesting(false)

                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: displayedW, height: displayedH)
                            .offset(x: offsetX, y: offsetY)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { v in
                                        let localX = (v.location.x - offsetX) / scale
                                        let localY = (v.location.y - offsetY) / scale
                                        let half = CGFloat(side) / 2
                                        let nx = (localX - half).clamped(0, pw - CGFloat(side))
                                        let ny = (localY - half).clamped(0, ph - CGFloat(side))
                                        origin = CGPoint(x: nx, y: ny)
                                    }
                            )
                    }
                    .frame(width: maxBox.width, height: maxBox.height)
                }
                .frame(minHeight: 320)

                HStack {
                    Button("Center") {
                        origin = CGPoint(x: (pw - CGFloat(side)) / 2,
                                         y: (ph - CGFloat(side)) / 2)
                    }
                    Spacer()
                    Button("Clear Custom") {
                        item.customCropOrigin = nil
                        onDone()
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .navigationTitle("Choose Thumbnail Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDone() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        item.customCropOrigin = origin
                        onDone()
                    }.bold()
                }
            }
            .onAppear {
                image = UIImage(contentsOfFile: item.url.path)
                if let existing = item.customCropOrigin {
                    origin = existing
                } else {
                    origin = CGPoint(x: (pw - CGFloat(side)) / 2,
                                     y: (ph - CGFloat(side)) / 2)
                }
            }
        }
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lo), Swift.max(lo, hi))
    }
}
