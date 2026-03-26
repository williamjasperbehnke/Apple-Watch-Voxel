import SwiftUI

struct GameView: View {
    private let rows = 9
    private let cols = 9

    let worldID: String

    @StateObject private var world: WorldStore
    @State private var selectedKind: BlockKind = .red
    @State private var suppressTap = false
    @State private var rotationIndex = 0.0
    @State private var isPanning = false
    @State private var isDragging = false
    @State private var panStartCenter = CGPoint.zero
    @State private var cameraCenter = CGPoint(
        x: CGFloat(WorldStore.worldSize / 2),
        y: CGFloat(WorldStore.worldSize / 2)
    )
    @State private var buildHeight = 1
    @State private var aimTile: AimTile?

    init(worldID: String) {
        self.worldID = worldID
        _world = StateObject(wrappedValue: WorldStore(worldID: worldID))
    }

    var body: some View {
        ZStack {
            sceneView
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inventoryBar
                .padding(.bottom, 4)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("R \(rotationLabel)")
                    Text("X \(Int(cameraCenter.x))")
                    Text("Z \(Int(cameraCenter.y))")
                    Text("Y \(buildHeight)")
                }
            }
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.35), in: Capsule())
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .focusable(true)
        .digitalCrownRotation(
            $rotationIndex,
            from: 0,
            through: 4,
            by: 1,
            sensitivity: .low,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    adjustHeight(-1)
                } label: {
                    Image(systemName: "minus")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    adjustHeight(1)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private var sceneView: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let _ = world.revision
                let tileWidth = min(size.width, size.height) / 6.6
                let tileHeight = tileWidth * 0.5
                let elevation = tileHeight * 1.2
                let origin = originPoint(size: size, tileHeight: tileHeight, elevation: elevation)
                let viewCenter = CGPoint(x: CGFloat(cols - 1) / 2, y: CGFloat(rows - 1) / 2)
                let angle = CGFloat(rotationIndex) * (.pi / 2)
                let cosA = cos(angle)
                let sinA = sin(angle)

                var samples: [TileSample] = []
                samples.reserveCapacity(rows * cols)
                for r in 0..<rows {
                    for c in 0..<cols {
                        let worldRow = Int(round(cameraCenter.y + (CGFloat(r) - viewCenter.y)))
                        let worldCol = Int(round(cameraCenter.x + (CGFloat(c) - viewCenter.x)))
                        guard WorldStore.inBounds(row: worldRow, col: worldCol) else { continue }
                        let localX = CGFloat(worldCol) - cameraCenter.x
                        let localY = CGFloat(worldRow) - cameraCenter.y
                        let rotX = localX * cosA - localY * sinA
                        let rotY = localX * sinA + localY * cosA
                        samples.append(TileSample(worldRow: worldRow, worldCol: worldCol, rotX: rotX, rotY: rotY))
                    }
                }
                samples.sort { $0.depth < $1.depth }

                let heightPlane = min(max(buildHeight, 1), world.maxHeight)
                for sample in samples {
                    let base = isoPoint(
                        rotX: sample.rotX,
                        rotY: sample.rotY,
                        origin: origin,
                        tileWidth: tileWidth,
                        tileHeight: tileHeight
                    )
                    drawGrid(
                        in: &context,
                        base: base,
                        tileWidth: tileWidth,
                        tileHeight: tileHeight,
                        elevation: elevation * CGFloat(max(heightPlane - 1, 0))
                    )
                }

                if let aim = aimTile {
                    if let sample = samples.first(where: { $0.worldRow == aim.row && $0.worldCol == aim.col }) {
                        let base = isoPoint(
                            rotX: sample.rotX,
                            rotY: sample.rotY,
                            origin: origin,
                            tileWidth: tileWidth,
                            tileHeight: tileHeight
                        )
                        drawGhost(
                            in: &context,
                            base: base,
                            tileWidth: tileWidth,
                            tileHeight: tileHeight,
                            height: heightPlane,
                            elevation: elevation,
                            kind: selectedKind,
                            angle: angle
                        )
                    }
                }

                let showOnlyHeight = aimTile != nil
                var visibleBlocks: [VisibleBlock] = []
                visibleBlocks.reserveCapacity(samples.count * world.maxHeight)
                for sample in samples {
                    if showOnlyHeight {
                        let block = world.block(at: sample.worldRow, col: sample.worldCol, height: heightPlane)
                        guard block != .empty else { continue }
                        let depth = sample.depth + CGFloat(heightPlane) * 0.01
                        visibleBlocks.append(
                            VisibleBlock(
                                sample: sample,
                                block: block,
                                height: heightPlane,
                                depth: depth
                            )
                        )
                    } else {
                        for height in 1...world.maxHeight {
                            let block = world.block(at: sample.worldRow, col: sample.worldCol, height: height)
                            guard block != .empty else { continue }
                            let depth = sample.depth + CGFloat(height) * 0.01
                            visibleBlocks.append(
                                VisibleBlock(
                                    sample: sample,
                                    block: block,
                                    height: height,
                                    depth: depth
                                )
                            )
                        }
                    }
                }
                visibleBlocks.sort { $0.depth < $1.depth }

                for item in visibleBlocks {
                    let base = isoPoint(
                        rotX: item.sample.rotX,
                        rotY: item.sample.rotY,
                        origin: origin,
                        tileWidth: tileWidth,
                        tileHeight: tileHeight
                    )
                    drawTile(
                        in: &context,
                        base: base,
                        tileWidth: tileWidth,
                        tileHeight: tileHeight,
                        topElevation: elevation * CGFloat(item.height),
                        bottomElevation: elevation * CGFloat(item.height - 1),
                        kind: item.block,
                        angle: angle
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard !suppressTap else { return }
                        if let aim = aimTile, isDragging {
                            paintTile(row: aim.row, col: aim.col)
                            aimTile = nil
                            isDragging = false
                            isPanning = false
                            return
                        }
                        isDragging = false
                        let size = proxy.size
                        let tileWidth = min(size.width, size.height) / 6.6
                        let tileHeight = tileWidth * 0.5
                        let elevation = tileHeight * 1.2
                        let origin = originPoint(size: size, tileHeight: tileHeight, elevation: elevation)
                        let center = cameraCenter
                        let angle = CGFloat(rotationIndex) * (.pi / 2)
                        let heightPlane = min(max(buildHeight, 1), world.maxHeight)
                        let hitPoint = adjustedPoint(value.location, height: heightPlane, elevation: elevation)
                        if let hit = hitTest(
                            point: hitPoint,
                            origin: origin,
                            tileWidth: tileWidth,
                            tileHeight: tileHeight,
                            center: center,
                            angle: angle
                        ), !isPanning {
                            handleTap(row: hit.row, col: hit.col)
                        }
                        isPanning = false
                    }
                    .onChanged { value in
                        guard !suppressTap else { return }
                        let distance = hypot(value.translation.width, value.translation.height)
                        isDragging = distance > 4
                        if aimTile != nil {
                            let size = proxy.size
                            let tileWidth = min(size.width, size.height) / 6.6
                            let tileHeight = tileWidth * 0.5
                            let elevation = tileHeight * 1.2
                            let origin = originPoint(size: size, tileHeight: tileHeight, elevation: elevation)
                            let center = cameraCenter
                            let angle = CGFloat(rotationIndex) * (.pi / 2)
                            let heightPlane = min(max(buildHeight, 1), world.maxHeight)
                            let hitPoint = adjustedPoint(value.location, height: heightPlane, elevation: elevation)
                            if let hit = hitTest(
                                point: hitPoint,
                                origin: origin,
                                tileWidth: tileWidth,
                                tileHeight: tileHeight,
                                center: center,
                                angle: angle
                            ) {
                                aimTile = AimTile(row: hit.row, col: hit.col)
                            }
                            if distance > 8 {
                                isPanning = true
                            }
                            return
                        }
                        if !isPanning, distance > 8 {
                            isPanning = true
                            panStartCenter = cameraCenter
                        }
                        if isPanning {
                            let size = proxy.size
                            let tileWidth = min(size.width, size.height) / 6.6
                            let tileHeight = tileWidth * 0.5
                            let angle = CGFloat(rotationIndex) * (.pi / 2)
                            let delta = worldDelta(
                                translation: value.translation,
                                tileWidth: tileWidth,
                                tileHeight: tileHeight,
                                angle: angle
                            )
                            cameraCenter = clampCameraCenter(
                                CGPoint(
                                    x: panStartCenter.x - delta.x,
                                    y: panStartCenter.y - delta.y
                                )
                            )
                        }
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        guard case let .second(true, drag?) = value else { return }
                        if isDragging {
                            return
                        }
                        suppressTap = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            suppressTap = false
                        }
                        if aimTile != nil {
                            aimTile = nil
                            return
                        }
                        let size = proxy.size
                        let tileWidth = min(size.width, size.height) / 6.6
                        let tileHeight = tileWidth * 0.5
                        let elevation = tileHeight * 1.2
                        let origin = originPoint(size: size, tileHeight: tileHeight, elevation: elevation)
                        let center = cameraCenter
                        let angle = CGFloat(rotationIndex) * (.pi / 2)
                        let heightPlane = min(max(buildHeight, 1), world.maxHeight)
                        let hitPoint = adjustedPoint(drag.location, height: heightPlane, elevation: elevation)
                        if let hit = hitTest(
                            point: hitPoint,
                            origin: origin,
                            tileWidth: tileWidth,
                            tileHeight: tileHeight,
                            center: center,
                            angle: angle
                        ) {
                            removeBlock(row: hit.row, col: hit.col)
                        }
                    }
            )
        }
    }

    private var inventoryBar: some View {
        HStack(spacing: 4) {
            ForEach(BlockKind.placeable, id: \.self) { kind in
                Button {
                    selectedKind = kind
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(kind.color)
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(selectedKind == kind ? 0.9 : 0.25), lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.black.opacity(0.35), in: Capsule())
    }

    private func paintTile(row: Int, col: Int) {
        guard WorldStore.inBounds(row: row, col: col) else { return }
        let height = min(max(buildHeight, 1), world.maxHeight)
        world.setBlock(row: row, col: col, height: height, block: selectedKind)
    }

    private func removeBlock(row: Int, col: Int) {
        guard WorldStore.inBounds(row: row, col: col) else { return }
        let height = min(max(buildHeight, 1), world.maxHeight)
        world.setBlock(row: row, col: col, height: height, block: .empty)
    }

    private var rotationLabel: String {
        let index = Int(rotationIndex.rounded()) % 4
        switch index {
        case 1: return "90"
        case 2: return "180"
        case 3: return "270"
        default: return "0"
        }
    }

    private func handleTap(row: Int, col: Int) {
        if let aim = aimTile {
            paintTile(row: aim.row, col: aim.col)
            aimTile = nil
        } else {
            aimTile = AimTile(row: row, col: col)
        }
    }

    private func originPoint(size: CGSize, tileHeight: CGFloat, elevation: CGFloat) -> CGPoint {
        let baseFactor: CGFloat = 0.45
        let baseY = size.height * baseFactor
        let heightPlane = CGFloat(min(max(buildHeight, 1), world.maxHeight))
        let yOffset = elevation * max(heightPlane - 1, 0) + 20
        let y = baseY + yOffset
        return CGPoint(x: size.width / 2, y: y)
    }

    private func adjustHeight(_ delta: Int) {
        let next = buildHeight + delta
        buildHeight = min(max(next, 1), world.maxHeight)
    }
}

private struct TileSample {
    let worldRow: Int
    let worldCol: Int
    let rotX: CGFloat
    let rotY: CGFloat

    var depth: CGFloat {
        rotX + rotY
    }
}

private struct VisibleBlock {
    let sample: TileSample
    let block: BlockKind
    let height: Int
    let depth: CGFloat
}

private struct AimTile: Hashable {
    let row: Int
    let col: Int
}

private func isoPoint(
    rotX: CGFloat,
    rotY: CGFloat,
    origin: CGPoint,
    tileWidth: CGFloat,
    tileHeight: CGFloat
) -> CGPoint {
    let x = (rotX - rotY) * tileWidth / 2 + origin.x
    let y = (rotX + rotY) * tileHeight / 2 + origin.y
    return CGPoint(x: x, y: y)
}

private func drawTile(
    in context: inout GraphicsContext,
    base: CGPoint,
    tileWidth: CGFloat,
    tileHeight: CGFloat,
    topElevation: CGFloat,
    bottomElevation: CGFloat,
    kind: BlockKind,
    angle: CGFloat
) {
    let halfW = tileWidth / 2
    let halfH = tileHeight / 2

    let top = Path { path in
        path.move(to: CGPoint(x: base.x, y: base.y - topElevation))
        path.addLine(to: CGPoint(x: base.x + halfW, y: base.y + halfH - topElevation))
        path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - topElevation))
        path.addLine(to: CGPoint(x: base.x - halfW, y: base.y + halfH - topElevation))
        path.closeSubpath()
    }

    if topElevation > bottomElevation {
        let leftShade = faceShade(direction: CGVector(dx: 0, dy: 1), angle: angle)
        let rightShade = faceShade(direction: CGVector(dx: 1, dy: 0), angle: angle)
        let right = Path { path in
            path.move(to: CGPoint(x: base.x + halfW, y: base.y + halfH - topElevation))
            path.addLine(to: CGPoint(x: base.x + halfW, y: base.y + halfH - bottomElevation))
            path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - bottomElevation))
            path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - topElevation))
            path.closeSubpath()
        }

        let left = Path { path in
            path.move(to: CGPoint(x: base.x - halfW, y: base.y + halfH - topElevation))
            path.addLine(to: CGPoint(x: base.x - halfW, y: base.y + halfH - bottomElevation))
            path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - bottomElevation))
            path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - topElevation))
            path.closeSubpath()
        }

        context.fill(left, with: .color(kind.color.opacity(leftShade)))
        context.fill(right, with: .color(kind.color.opacity(rightShade)))
    }

    context.fill(top, with: .color(kind.color))
    context.stroke(top, with: .color(Color.black.opacity(0.35)), lineWidth: 1)
}

private func drawGrid(
    in context: inout GraphicsContext,
    base: CGPoint,
    tileWidth: CGFloat,
    tileHeight: CGFloat,
    elevation: CGFloat
) {
    let halfW = tileWidth / 2
    let halfH = tileHeight / 2
    let outline = Path { path in
        path.move(to: CGPoint(x: base.x, y: base.y - elevation))
        path.addLine(to: CGPoint(x: base.x + halfW, y: base.y + halfH - elevation))
        path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - elevation))
        path.addLine(to: CGPoint(x: base.x - halfW, y: base.y + halfH - elevation))
        path.closeSubpath()
    }
    context.stroke(outline, with: .color(Color.white.opacity(0.15)), lineWidth: 1)
}

private func drawGhost(
    in context: inout GraphicsContext,
    base: CGPoint,
    tileWidth: CGFloat,
    tileHeight: CGFloat,
    height: Int,
    elevation: CGFloat,
    kind: BlockKind,
    angle: CGFloat
) {
    let halfW = tileWidth / 2
    let halfH = tileHeight / 2
    let topElevation = elevation * CGFloat(height)
    let bottomElevation = elevation * CGFloat(max(height - 1, 0))

    let top = Path { path in
        path.move(to: CGPoint(x: base.x, y: base.y - topElevation))
        path.addLine(to: CGPoint(x: base.x + halfW, y: base.y + halfH - topElevation))
        path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - topElevation))
        path.addLine(to: CGPoint(x: base.x - halfW, y: base.y + halfH - topElevation))
        path.closeSubpath()
    }

    if topElevation > bottomElevation {
        let leftShade = faceShade(direction: CGVector(dx: 0, dy: 1), angle: angle)
        let rightShade = faceShade(direction: CGVector(dx: 1, dy: 0), angle: angle)
        let right = Path { path in
            path.move(to: CGPoint(x: base.x + halfW, y: base.y + halfH - topElevation))
            path.addLine(to: CGPoint(x: base.x + halfW, y: base.y + halfH - bottomElevation))
            path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - bottomElevation))
            path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - topElevation))
            path.closeSubpath()
        }

        let left = Path { path in
            path.move(to: CGPoint(x: base.x - halfW, y: base.y + halfH - topElevation))
            path.addLine(to: CGPoint(x: base.x - halfW, y: base.y + halfH - bottomElevation))
            path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - bottomElevation))
            path.addLine(to: CGPoint(x: base.x, y: base.y + tileHeight - topElevation))
            path.closeSubpath()
        }

        context.fill(left, with: .color(kind.color.opacity(0.25 * leftShade)))
        context.fill(right, with: .color(kind.color.opacity(0.25 * rightShade)))
    }

    context.fill(top, with: .color(kind.color.opacity(0.35)))
    context.stroke(top, with: .color(Color.white.opacity(0.35)), lineWidth: 1)
}

private func clampCameraCenter(_ point: CGPoint) -> CGPoint {
    let maxIndex = CGFloat(WorldStore.worldSize - 1)
    return CGPoint(
        x: min(max(point.x, 0), maxIndex),
        y: min(max(point.y, 0), maxIndex)
    )
}

private func adjustedPoint(_ point: CGPoint, height: Int, elevation: CGFloat) -> CGPoint {
    let offset = elevation * CGFloat(max(height - 1, 0))
    return CGPoint(x: point.x, y: point.y + offset)
}

private func worldDelta(translation: CGSize, tileWidth: CGFloat, tileHeight: CGFloat, angle: CGFloat) -> CGPoint {
    let rotX = (translation.width / (tileWidth / 2) + translation.height / (tileHeight / 2)) / 2
    let rotY = (translation.height / (tileHeight / 2) - translation.width / (tileWidth / 2)) / 2
    let cosA = cos(angle)
    let sinA = sin(angle)
    let deltaCol = rotX * cosA + rotY * sinA
    let deltaRow = -rotX * sinA + rotY * cosA
    return CGPoint(x: deltaCol, y: deltaRow)
}

private func faceShade(direction: CGVector, angle: CGFloat) -> Double {
    let cosA = cos(angle)
    let sinA = sin(angle)
    let rotX = direction.dx * cosA - direction.dy * sinA
    let rotY = direction.dx * sinA + direction.dy * cosA
    let light = CGVector(dx: -0.7, dy: -0.7)
    let dot = rotX * light.dx + rotY * light.dy
    let normalized = max(min((dot + 1) / 2, 1), 0)
    return 0.55 + 0.35 * Double(normalized)
}

private func hitTest(
    point: CGPoint,
    origin: CGPoint,
    tileWidth: CGFloat,
    tileHeight: CGFloat,
    center: CGPoint,
    angle: CGFloat
) -> (row: Int, col: Int)? {
    let localX = point.x - origin.x
    let localY = point.y - origin.y
    let rotX = (localX / (tileWidth / 2) + localY / (tileHeight / 2)) / 2
    let rotY = (localY / (tileHeight / 2) - localX / (tileWidth / 2)) / 2
    let cosA = cos(angle)
    let sinA = sin(angle)
    let localCol = rotX * cosA + rotY * sinA
    let localRow = -rotX * sinA + rotY * cosA
    let row = localRow + center.y
    let col = localCol + center.x
    let r = Int(floor(row + 0.5))
    let c = Int(floor(col + 0.5))
    guard WorldStore.inBounds(row: r, col: c) else { return nil }
    return (r, c)
}
