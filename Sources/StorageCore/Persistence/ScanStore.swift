import Foundation

public enum ScanStoreError: Error, Equatable {
    case corrupted
    case unsupportedVersion(UInt32)
}

/// Sauvegarde et rechargement du dernier scan (format binaire versionné, compressé en LZFSE).
public struct ScanStore: Sendable {
    public static let formatVersion: UInt32 = 1
    static let magic: [UInt8] = Array("SMSC".utf8)

    public let fileURL: URL

    public init(directory: URL = ScanStore.defaultDirectory) {
        fileURL = directory.appendingPathComponent("last-scan.bin")
    }

    /// `~/Library/Application Support/StorageMonitor/`
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StorageMonitor", isDirectory: true)
    }

    public func save(_ tree: FileTree) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let raw = Self.encode(tree)
        let compressed = try (raw as NSData).compressed(using: .lzfse) as Data
        try compressed.write(to: fileURL, options: .atomic)
    }

    /// `nil` s'il n'y a pas encore de scan enregistré.
    public func load() throws -> FileTree? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let compressed = try Data(contentsOf: fileURL)
        guard let raw = try? (compressed as NSData).decompressed(using: .lzfse) as Data else {
            throw ScanStoreError.corrupted
        }
        return try Self.decode(raw)
    }

    // MARK: - Format

    /// Nœuds vivants en pré-ordre : un parent précède toujours ses enfants.
    static func encode(_ tree: FileTree) -> Data {
        var writer = BinaryWriter()
        writer.bytes(magic)
        writer.integer(formatVersion)
        writer.string(tree.rootPath)
        writer.integer(tree.scanDate.timeIntervalSince1970.bitPattern)
        writer.integer(UInt32(tree.unreadablePaths.count))
        for path in tree.unreadablePaths { writer.string(path) }

        var order: [NodeID] = []
        order.reserveCapacity(tree.storageCount)
        var newIndex = [Int32](repeating: -1, count: tree.storageCount)
        var stack: [NodeID] = [tree.root]
        while let node = stack.popLast() {
            newIndex[Int(node)] = Int32(order.count)
            order.append(node)
            stack.append(contentsOf: tree.children(of: node).reversed())
        }

        writer.integer(UInt32(order.count))
        for node in order {
            let parent = tree.parent(of: node).map { newIndex[Int($0)] } ?? -1
            writer.integer(parent)
            writer.integer(tree.nodeType(of: node).rawValue)
            writer.integer(tree.kind(of: node).rawValue)
            writer.integer(tree.size(of: node))
            writer.integer(tree.modDates[Int(node)])
            writer.string(tree.name(of: node))
        }
        return Data(writer.buffer)
    }

    static func decode(_ data: Data) throws -> FileTree {
        var reader = BinaryReader(bytes: [UInt8](data))
        guard try reader.bytes(count: magic.count) == magic else { throw ScanStoreError.corrupted }
        let version = try reader.integer(UInt32.self)
        guard version == formatVersion else { throw ScanStoreError.unsupportedVersion(version) }
        let rootPath = try reader.string()
        let scanDate = Date(timeIntervalSince1970: Double(bitPattern: try reader.integer(UInt64.self)))
        let unreadableCount = Int(try reader.integer(UInt32.self))
        var unreadable: [String] = []
        for _ in 0..<unreadableCount { unreadable.append(try reader.string()) }

        let count = Int(try reader.integer(UInt32.self))
        guard count >= 1 else { throw ScanStoreError.corrupted }
        var names: [String] = [], parents: [NodeID] = [], types: [NodeType] = []
        var kinds: [ContentKind] = [], sizes: [UInt64] = [], modDates: [Int64] = []
        names.reserveCapacity(count); parents.reserveCapacity(count); types.reserveCapacity(count)
        kinds.reserveCapacity(count); sizes.reserveCapacity(count); modDates.reserveCapacity(count)

        for i in 0..<count {
            let parent = try reader.integer(Int32.self)
            guard (i == 0 && parent == -1) || (i > 0 && parent >= 0 && Int(parent) < i) else {
                throw ScanStoreError.corrupted
            }
            guard let type = NodeType(rawValue: try reader.integer(UInt8.self)),
                  let kind = ContentKind(rawValue: try reader.integer(UInt8.self)) else {
                throw ScanStoreError.corrupted
            }
            parents.append(parent)
            types.append(type)
            kinds.append(kind)
            sizes.append(try reader.integer(UInt64.self))
            modDates.append(try reader.integer(Int64.self))
            names.append(try reader.string())
        }
        guard reader.isAtEnd else { throw ScanStoreError.corrupted }
        return FileTree(rootPath: rootPath, scanDate: scanDate, unreadablePaths: unreadable,
                        names: names, parents: parents, types: types, kinds: kinds,
                        sizes: sizes, modDates: modDates)
    }
}

struct BinaryWriter {
    private(set) var buffer: [UInt8] = []

    mutating func bytes(_ bytes: [UInt8]) { buffer.append(contentsOf: bytes) }

    mutating func integer<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { buffer.append(contentsOf: $0) }
    }

    mutating func string(_ value: String) {
        let utf8 = Array(value.utf8)
        integer(UInt32(utf8.count))
        buffer.append(contentsOf: utf8)
    }
}

struct BinaryReader {
    let bytes: [UInt8]
    private var offset = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func bytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw ScanStoreError.corrupted }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func integer<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= bytes.count else { throw ScanStoreError.corrupted }
        let value = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
        offset += size
        return T(littleEndian: value)
    }

    mutating func string() throws -> String {
        let length = Int(try integer(UInt32.self))
        guard offset + length <= bytes.count else { throw ScanStoreError.corrupted }
        defer { offset += length }
        return String(decoding: bytes[offset..<offset + length], as: UTF8.self)
    }
}
