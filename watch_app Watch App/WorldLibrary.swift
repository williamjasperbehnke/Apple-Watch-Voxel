import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WorldLibrary {
    static func listWorlds() -> [String] {
        do {
            let folder = try worldsFolder()
            let items = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            let names = items
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
            return names.sorted()
        } catch {
            return []
        }
    }

    static func bootstrapSampleWorlds() {
        guard listWorlds().isEmpty else { return }
        createSampleWorlds()
    }

    static func createWorld(named name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "world" : trimmed
        let slug = slugify(base)
        let final = slug.isEmpty ? "world" : slug
        let unique = uniquedName(final)
        let data = WorldData(
            worldSize: WorldStore.worldSize,
            chunkSize: WorldStore.chunkSize,
            maxHeight: Chunk.maxHeight,
            seed: Int.random(in: 1...Int.max),
            chunks: []
        )
        do {
            let url = try worldURL(worldID: unique)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(data)
            try encoded.write(to: url, options: [.atomic])
        } catch {
            return unique
        }
        return unique
    }

    static func deleteWorld(named name: String) {
        do {
            let url = try worldURL(worldID: name)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            // Ignore deletion errors for now.
        }
    }

    static func exportWorldPNG(named name: String) -> URL? {
        guard let data = loadWorldData(named: name) else { return nil }
        let size = WorldStore.worldSize
        var pixels = Array(repeating: UInt8(0), count: size * size * 4)

        let maxHeight = min(data.maxHeight ?? Chunk.maxHeight, Chunk.maxHeight)
        for record in data.chunks {
            let chunk = record.chunk
            let baseRow = record.coord.y * Chunk.size
            let baseCol = record.coord.x * Chunk.size
            for r in 0..<Chunk.size {
                for c in 0..<Chunk.size {
                    let worldRow = baseRow + r
                    let worldCol = baseCol + c
                    guard worldRow < size, worldCol < size else { continue }
                    var topBlock: BlockKind = .empty
                    for h in stride(from: maxHeight, through: 1, by: -1) {
                        let block = chunk.get(row: r, col: c, height: h - 1)
                        if block != .empty {
                            topBlock = block
                            break
                        }
                    }
                    guard topBlock != .empty else { continue }
                    let index = (worldRow * size + worldCol) * 4
                    let rgba = topBlock.rgba
                    pixels[index] = rgba.r
                    pixels[index + 1] = rgba.g
                    pixels[index + 2] = rgba.b
                    pixels[index + 3] = rgba.a
                }
            }
        }

        let bytesPerRow = size * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        guard let image = CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        do {
            let folder = try exportsFolder()
            let url = folder.appendingPathComponent("\(name).png")
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return url
        } catch {
            return nil
        }
    }

    static func listExports() -> [String] {
        do {
            let folder = try exportsFolder()
            let items = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            return items
                .filter { $0.pathExtension.lowercased() == "png" }
                .map { $0.lastPathComponent }
                .sorted()
        } catch {
            return []
        }
    }

    static func exportURL(for filename: String) -> URL? {
        do {
            let folder = try exportsFolder()
            return folder.appendingPathComponent(filename)
        } catch {
            return nil
        }
    }

    static func loadExportImage(named filename: String) -> CGImage? {
        guard let url = exportURL(for: filename) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func loadWorldData(named name: String) -> WorldData? {
        do {
            let url = try worldURL(worldID: name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WorldData.self, from: data)
        } catch {
            return nil
        }
    }

    private static func exportsFolder() throws -> URL {
        let base = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return folder
    }

    private static func createSampleWorlds() {
        writeRainbowRingWorld(named: "rainbow-ring")
        writeSmileWorld(named: "smile-world")
        writeCheckerStepsWorld(named: "checker-steps")
        writeColorBorderWorld(named: "color-border-128")
    }

    private static func writeRainbowRingWorld(named name: String) {
        var chunks: [ChunkCoord: Chunk] = [:]
        let center = 64
        let radius = 20
        let thickness = 2
        let palette: [BlockKind] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]

        for r in (center - 40)...(center + 40) {
            for c in (center - 40)...(center + 40) {
                let dx = c - center
                let dy = r - center
                let dist = Int(round(sqrt(Double(dx * dx + dy * dy))))
                if dist >= radius - thickness && dist <= radius + thickness {
                    let angle = atan2(Double(dy), Double(dx))
                    let t = (angle + Double.pi) / (2 * Double.pi)
                    let idx = Int(floor(t * Double(palette.count))) % palette.count
                    setBlock(&chunks, row: r, col: c, height: 1, block: palette[idx])
                }
            }
        }

        for h in 1...Chunk.maxHeight {
            let color = palette[(h - 1) % palette.count]
            setBlock(&chunks, row: center, col: center, height: h, block: color)
        }

        writeWorld(named: name, chunks: chunks)
    }

    private static func writeSmileWorld(named name: String) {
        var chunks: [ChunkCoord: Chunk] = [:]
        let center = 64
        let radius = 18
        for r in (center - 28)...(center + 28) {
            for c in (center - 28)...(center + 28) {
                let dx = c - center
                let dy = r - center
                let dist = sqrt(Double(dx * dx + dy * dy))
                if dist <= Double(radius) {
                    setBlock(&chunks, row: r, col: c, height: 1, block: .yellow)
                }
            }
        }

        for r in (center - 7)..<(center - 3) {
            for c in (center - 8)..<(center - 4) {
                setBlock(&chunks, row: r, col: c, height: 2, block: .blue)
            }
        }
        for r in (center - 7)..<(center - 3) {
            for c in (center + 4)..<(center + 8) {
                setBlock(&chunks, row: r, col: c, height: 2, block: .blue)
            }
        }
        for x in -10...10 {
            let y = Int(round(sqrt(Double(10 * 10 - x * x))))
            setBlock(&chunks, row: center + 6 + y, col: center + x, height: 2, block: .red)
        }

        writeWorld(named: name, chunks: chunks)
    }

    private static func writeCheckerStepsWorld(named name: String) {
        var chunks: [ChunkCoord: Chunk] = [:]
        let center = 64
        for r in (center - 32)...(center + 32) {
            for c in (center - 32)...(center + 32) {
                let base = ((r + c) % 2 == 0) ? BlockKind.green : BlockKind.purple
                setBlock(&chunks, row: r, col: c, height: 1, block: base)
                let height = min((r + c) / 12 + 1, Chunk.maxHeight)
                if height > 1 {
                    setBlock(&chunks, row: r, col: c, height: height, block: .cyan)
                }
            }
        }
        writeWorld(named: name, chunks: chunks)
    }

    private static func writeColorBorderWorld(named name: String) {
        var chunks: [ChunkCoord: Chunk] = [:]
        let size = WorldStore.worldSize
        let palette: [BlockKind] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]

        for x in 0..<size {
            let topColor = palette[x % palette.count]
            let bottomColor = palette[(x + 3) % palette.count]
            setBlock(&chunks, row: 0, col: x, height: 1, block: topColor)
            setBlock(&chunks, row: size - 1, col: x, height: 1, block: bottomColor)
        }

        for y in 0..<size {
            let leftColor = palette[(y + 1) % palette.count]
            let rightColor = palette[(y + 5) % palette.count]
            setBlock(&chunks, row: y, col: 0, height: 1, block: leftColor)
            setBlock(&chunks, row: y, col: size - 1, height: 1, block: rightColor)
        }

        writeWorld(named: name, chunks: chunks)
    }

    private static func writeWorld(named name: String, chunks: [ChunkCoord: Chunk]) {
        let data = WorldData(
            worldSize: WorldStore.worldSize,
            chunkSize: WorldStore.chunkSize,
            maxHeight: Chunk.maxHeight,
            seed: Int.random(in: 1...Int.max),
            chunks: chunks.map { ChunkRecord(coord: $0.key, chunk: $0.value) }
        )
        do {
            let url = try worldURL(worldID: name)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(data)
            try encoded.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private static func setBlock(
        _ chunks: inout [ChunkCoord: Chunk],
        row: Int,
        col: Int,
        height: Int,
        block: BlockKind
    ) {
        guard row >= 0, col >= 0, row < WorldStore.worldSize, col < WorldStore.worldSize else { return }
        guard height >= 1, height <= Chunk.maxHeight else { return }
        let coord = ChunkCoord(x: col / Chunk.size, y: row / Chunk.size)
        var chunk = chunks[coord] ?? Chunk()
        let localRow = row % Chunk.size
        let localCol = col % Chunk.size
        chunk.set(row: localRow, col: localCol, height: height - 1, block: block)
        chunks[coord] = chunk
    }

    private static func worldsFolder() throws -> URL {
        let base = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("Worlds", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return folder
    }

    private static func worldURL(worldID: String) throws -> URL {
        let folder = try worldsFolder()
        return folder.appendingPathComponent("\(worldID).json")
    }

    private static func slugify(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let cleaned = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .map { allowed.contains($0.unicodeScalars.first!) ? String($0) : "" }
            .joined()
        return cleaned
    }

    private static func uniquedName(_ base: String) -> String {
        var candidate = base
        var index = 1
        let existing = Set(listWorlds())
        while existing.contains(candidate) {
            index += 1
            candidate = "\(base)-\(index)"
        }
        return candidate
    }
}
