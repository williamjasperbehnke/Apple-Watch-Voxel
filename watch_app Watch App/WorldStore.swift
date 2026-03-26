import Foundation
import SwiftUI

final class WorldStore: ObservableObject {
    static let worldSize = 128
    static let chunkSize = Chunk.size

    let maxHeight = Chunk.maxHeight

    @Published private(set) var revision = 0

    private let worldID: String
    private var seed: Int
    private var chunks: [ChunkCoord: Chunk] = [:]
    private var saveWorkItem: DispatchWorkItem?

    init(worldID: String) {
        self.worldID = worldID
        if let data = Self.loadWorld(worldID: worldID) {
            seed = data.seed
            chunks = Dictionary(uniqueKeysWithValues: data.chunks.map { ($0.coord, $0.chunk) })
        } else {
            seed = Int.random(in: 1...Int.max)
        }
    }

    func block(at row: Int, col: Int, height: Int) -> BlockKind {
        guard Self.inBounds(row: row, col: col) else { return .empty }
        guard height >= 1, height <= maxHeight else { return .empty }

        let coord = chunkCoord(row: row, col: col)
        if chunks[coord] == nil {
            chunks[coord] = generateChunk(coord: coord)
        }

        let (localRow, localCol) = localCoord(row: row, col: col)
        let layer = height - 1
        return chunks[coord]?.get(row: localRow, col: localCol, height: layer) ?? .empty
    }

    func setBlock(row: Int, col: Int, height: Int, block: BlockKind) {
        guard Self.inBounds(row: row, col: col) else { return }
        guard height >= 1, height <= maxHeight else { return }

        let coord = chunkCoord(row: row, col: col)
        var chunk = chunks[coord] ?? generateChunk(coord: coord)
        let (localRow, localCol) = localCoord(row: row, col: col)
        let layer = height - 1
        chunk.set(row: localRow, col: localCol, height: layer, block: block)

        chunks[coord] = chunk
        revision += 1
        scheduleSave()
    }

    static func inBounds(row: Int, col: Int) -> Bool {
        row >= 0 && col >= 0 && row < worldSize && col < worldSize
    }

    private func chunkCoord(row: Int, col: Int) -> ChunkCoord {
        ChunkCoord(x: col / Self.chunkSize, y: row / Self.chunkSize)
    }

    private func localCoord(row: Int, col: Int) -> (Int, Int) {
        (row % Self.chunkSize, col % Self.chunkSize)
    }

    private func generateChunk(coord: ChunkCoord) -> Chunk {
        Chunk(defaultBlock: .empty)
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.save()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    private func save() {
        let records = chunks.map { ChunkRecord(coord: $0.key, chunk: $0.value) }
        let data = WorldData(
            worldSize: Self.worldSize,
            chunkSize: Self.chunkSize,
            maxHeight: maxHeight,
            seed: seed,
            chunks: records
        )

        do {
            let url = try Self.worldURL(worldID: worldID)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(data)
            try encoded.write(to: url, options: [.atomic])
        } catch {
            // Best-effort save; avoid crashing on watch.
        }
    }

    private static func loadWorld(worldID: String) -> WorldData? {
        do {
            let url = try worldURL(worldID: worldID)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WorldData.self, from: data)
        } catch {
            return nil
        }
    }

    private static func worldURL(worldID: String) throws -> URL {
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
        return folder.appendingPathComponent("\(worldID).json")
    }

    deinit {
        save()
    }
}
