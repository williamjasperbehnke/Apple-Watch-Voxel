import SwiftUI

enum BlockKind: Int, CaseIterable, Codable {
    case empty = 0
    case red
    case yellow
    case blue
    case orange
    case green
    case purple
    case cyan

    var color: Color {
        switch self {
        case .empty: return .clear
        case .red: return Color(red: 0.86, green: 0.22, blue: 0.20)
        case .yellow: return Color(red: 0.96, green: 0.84, blue: 0.20)
        case .blue: return Color(red: 0.18, green: 0.42, blue: 0.86)
        case .orange: return Color(red: 0.95, green: 0.55, blue: 0.16)
        case .green: return Color(red: 0.18, green: 0.70, blue: 0.30)
        case .purple: return Color(red: 0.56, green: 0.28, blue: 0.78)
        case .cyan: return Color(red: 0.20, green: 0.78, blue: 0.86)
        }
    }

    static var placeable: [BlockKind] {
        [.red, .yellow, .blue, .orange, .green, .purple, .cyan]
    }

    var rgba: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        switch self {
        case .empty: return (0, 0, 0, 0)
        case .red: return (220, 56, 51, 255)
        case .yellow: return (245, 214, 51, 255)
        case .blue: return (46, 107, 219, 255)
        case .orange: return (242, 140, 41, 255)
        case .green: return (46, 179, 77, 255)
        case .purple: return (143, 71, 199, 255)
        case .cyan: return (51, 199, 219, 255)
        }
    }
}

struct Chunk: Codable {
    static let size = 16
    static let maxHeight = 8

    var blocks: [BlockKind]

    init(defaultBlock: BlockKind = .empty) {
        blocks = Array(repeating: defaultBlock, count: Chunk.size * Chunk.size * Chunk.maxHeight)
    }

    mutating func set(row: Int, col: Int, height: Int, block: BlockKind) {
        blocks[index(row: row, col: col, height: height)] = block
    }

    func get(row: Int, col: Int, height: Int) -> BlockKind {
        blocks[index(row: row, col: col, height: height)]
    }

    private func index(row: Int, col: Int, height: Int) -> Int {
        ((row * Chunk.size + col) * Chunk.maxHeight) + height
    }
}

struct ChunkCoord: Hashable, Codable {
    var x: Int
    var y: Int
}

struct ChunkRecord: Codable {
    var coord: ChunkCoord
    var chunk: Chunk
}

struct WorldData: Codable {
    var worldSize: Int
    var chunkSize: Int
    var maxHeight: Int?
    var seed: Int
    var chunks: [ChunkRecord]
}
