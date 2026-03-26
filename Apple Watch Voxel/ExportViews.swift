import SwiftUI

struct ExportListView: View {
    @State private var exports: [String] = []

    var body: some View {
        List {
            if exports.isEmpty {
                Text("No exports yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(exports, id: \.self) { filename in
                    NavigationLink(filename) {
                        ExportPreviewView(filename: filename)
                    }
                }
            }
        }
        .navigationTitle("Exports")
        .onAppear {
            exports = WorldLibrary.listExports()
        }
    }
}

struct ExportPreviewView: View {
    let filename: String

    @State private var zoomStep = 1.0
    @State private var panOffset = CGSize.zero
    @State private var panStart = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let baseScale = max(1, Int(min(proxy.size.width, proxy.size.height) / CGFloat(WorldStore.worldSize)))
            let scale = max(1, Int(zoomStep.rounded()))
            let size = CGFloat(WorldStore.worldSize * scale)
            ZStack {
                if let image = WorldLibrary.loadExportImage(named: filename) {
                    let maxPanX = max(0, (size - proxy.size.width) / 2)
                    let maxPanY = max(0, (size - proxy.size.height) / 2)
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: size, height: size)
                        .offset(panOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    panOffset = rubberPan(
                                        CGSize(
                                            width: panStart.width + value.translation.width,
                                            height: panStart.height + value.translation.height
                                        ),
                                        maxX: maxPanX,
                                        maxY: maxPanY
                                    )
                                }
                                .onEnded { _ in
                                    let clamped = clampPan(panOffset, maxX: maxPanX, maxY: maxPanY)
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        panOffset = clamped
                                    }
                                    panStart = clamped
                                }
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Text("Unable to load image.")
                        .foregroundStyle(.secondary)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .onAppear {
                if zoomStep == 1.0 {
                    zoomStep = Double(baseScale)
                }
            }
            .onChange(of: baseScale) { value in
                zoomStep = max(1, min(zoomStep, Double(max(8, value))))
            }
            .onChange(of: zoomStep) { _ in
                let maxPanX = max(0, (size - proxy.size.width) / 2)
                let maxPanY = max(0, (size - proxy.size.height) / 2)
                panOffset = clampPan(panOffset, maxX: maxPanX, maxY: maxPanY)
                panStart = panOffset
            }
        }
        .navigationTitle(filename)
        .focusable(true)
        .digitalCrownRotation(
            $zoomStep,
            from: 1,
            through: 8,
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }

    private func clampPan(_ offset: CGSize, maxX: CGFloat, maxY: CGFloat) -> CGSize {
        CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func rubberPan(_ offset: CGSize, maxX: CGFloat, maxY: CGFloat) -> CGSize {
        CGSize(
            width: rubberAxis(offset.width, limit: maxX),
            height: rubberAxis(offset.height, limit: maxY)
        )
    }

    private func rubberAxis(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        if value > limit {
            let overshoot = value - limit
            return limit + overshoot * 0.25
        }
        if value < -limit {
            let overshoot = value + limit
            return -limit + overshoot * 0.25
        }
        return value
    }
}
