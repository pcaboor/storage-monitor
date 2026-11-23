import Foundation
import Testing
@testable import StorageCore

@Suite struct VolumeInfoTests {
    @Test func readsTheBootVolume() throws {
        let info = try VolumeInfo.current(for: "/")
        #expect(info.totalCapacity > 0)
        #expect(info.availableCapacity <= info.totalCapacity)
        #expect(info.usedCapacity == info.totalCapacity - info.availableCapacity)
        #expect(!info.name.isEmpty)
    }

    @Test func systemOtherSizeNeverGoesNegative() {
        #expect(VolumeInfo.systemOtherSize(used: 100, scanned: 70) == 30)
        #expect(VolumeInfo.systemOtherSize(used: 70, scanned: 100) == 0)
    }
}

@Suite struct FullDiskAccessTests {
    @Test func readableProbeMeansGranted() throws {
        let tmp = try TempDir()
        #expect(FullDiskAccess.isGranted(probePaths: [tmp.path]))
    }

    @Test func deniedProbeMeansNotGranted() throws {
        let tmp = try TempDir()
        let locked = try tmp.dir("protégé")
        chmod(locked, 0o000)
        defer { chmod(locked, 0o755) }
        #expect(!FullDiskAccess.isGranted(probePaths: [locked]))
    }

    @Test func missingProbesAreInconclusive() throws {
        let tmp = try TempDir()
        #expect(FullDiskAccess.isGranted(probePaths: [tmp.path + "/absent"]))
    }
}
