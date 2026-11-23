import Testing
@testable import StorageCore

@Suite struct ContentKindTests {
    @Test(arguments: [
        ("film.MP4", ContentKind.video),
        ("photo.heic", .image),
        ("song.flac", .audio),
        ("main.swift", .code),
        ("Safari.app", .app),
        ("backup.tar.gz", .archive),
        ("Installer.dmg", .archive),
        ("rapport.pdf", .document),
        ("Docker.raw", .system),
        ("Makefile", .other),
        (".zshrc", .other),
    ])
    func classifiesByExtension(name: String, expected: ContentKind) {
        #expect(ContentKind.classify(fileName: name) == expected)
    }

    @Test func everyKindHasAFrenchLabel() {
        for kind in ContentKind.allCases { #expect(!kind.label.isEmpty) }
        #expect(ContentKind.video.label == "Vidéos")
    }

    @Test func detectsPackagesByExtension() {
        #expect(PackageDetector.isPackage(name: "Safari.app"))
        #expect(PackageDetector.isPackage(name: "Photos Library.photoslibrary"))
        #expect(PackageDetector.isPackage(name: "Projet.XCODEPROJ"))
        #expect(!PackageDetector.isPackage(name: "lodash.merge"))
        #expect(!PackageDetector.isPackage(name: ".app"))
        #expect(!PackageDetector.isPackage(name: "Documents"))
    }
}
