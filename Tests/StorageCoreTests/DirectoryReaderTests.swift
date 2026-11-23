import Foundation
import Testing
@testable import StorageCore

@Suite struct DirectoryReaderTests {
    @Test func readsNamesKindsAndAllocatedSizes() throws {
        let tmp = try TempDir()
        let file = try tmp.file("doc.txt", bytes: 10_000)
        try tmp.dir("sub")
        try FileManager.default.createSymbolicLink(atPath: tmp.path + "/lien", withDestinationPath: file)

        let listing = try DirectoryReader.read(path: tmp.path)
        let byName = Dictionary(uniqueKeysWithValues: listing.entries.map { ($0.name, $0) })

        #expect(byName.count == 3)
        #expect(byName["doc.txt"]?.kind == .file)
        #expect(byName["doc.txt"]?.allocatedSize == allocatedSize(file))
        #expect(byName["doc.txt"]?.linkCount == 1)
        #expect(byName["sub"]?.kind == .directory)
        #expect(byName["sub"]?.allocatedSize == 0)
        #expect(byName["lien"]?.kind == .symlink)

        let attrs = try FileManager.default.attributesOfItem(atPath: file)
        let mod = try #require(attrs[.modificationDate] as? Date)
        #expect(byName["doc.txt"]?.modificationTime == Int64(mod.timeIntervalSince1970))
        #expect(listing.device == deviceID(tmp.path))
    }

    @Test func readsNonAsciiNames() throws {
        let tmp = try TempDir()
        try tmp.file("café été 🎉.txt", bytes: 1)
        let listing = try DirectoryReader.read(path: tmp.path)
        #expect(listing.entries.map(\.name) == ["café été 🎉.txt"])
    }

    @Test func readsDirectoriesLargerThanOneBuffer() throws {
        let tmp = try TempDir()
        let longName = String(repeating: "n", count: 120)
        for i in 0..<3000 { try tmp.file("\(longName)-\(i)", bytes: 0) }
        let listing = try DirectoryReader.read(path: tmp.path)
        #expect(listing.entries.count == 3000)
        #expect(Set(listing.entries.map(\.name)).count == 3000)
    }

    @Test func reportsPosixErrors() throws {
        let tmp = try TempDir()
        let file = try tmp.file("f", bytes: 1)
        #expect(throws: DirectoryReadError.posix(ENOENT)) { try DirectoryReader.read(path: tmp.path + "/absent") }
        #expect(throws: DirectoryReadError.posix(ENOTDIR)) { try DirectoryReader.read(path: file) }
    }
}
