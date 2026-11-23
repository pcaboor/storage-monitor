import Darwin

/// Une entrée brute lue dans un dossier.
struct RawEntry: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case file, directory, symlink, other }

    var name: String
    var kind: Kind
    /// Taille réellement allouée sur le disque (0 pour les dossiers).
    var allocatedSize: UInt64
    /// Date de modification, en secondes depuis 1970.
    var modificationTime: Int64
    var linkCount: UInt32
    var fileID: UInt64
}

struct DirectoryListing: Sendable {
    /// Identifiant du volume qui contient le dossier.
    var device: Int32
    var entries: [RawEntry]
}

enum DirectoryReadError: Error, Equatable {
    case posix(Int32)
}

/// Lecture rapide d'un dossier par lots via `getattrlistbulk(2)`.
enum DirectoryReader {
    private static let bufferSize = 256 * 1024

    static func read(path: String) throws -> DirectoryListing {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw DirectoryReadError.posix(errno) }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0 else { throw DirectoryReadError.posix(errno) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FILEID)
        request.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var entries: [RawEntry] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if count < 0 {
                if errno == EINTR { continue }
                throw DirectoryReadError.posix(errno)
            }
            if count == 0 { break }

            var entryStart = buffer
            for _ in 0..<count {
                let length = entryStart.loadUnaligned(as: UInt32.self)
                defer { entryStart += Int(length) }
                if let entry = parseEntry(at: entryStart + MemoryLayout<UInt32>.size) {
                    entries.append(entry)
                }
            }
        }
        return DirectoryListing(device: info.st_dev, entries: entries)
    }

    /// Décode une entrée. Seuls les attributs signalés dans `ATTR_CMN_RETURNED_ATTRS` sont présents
    /// (un dossier n'a pas d'attributs de fichier), dans l'ordre de leurs bits.
    private static func parseEntry(at start: UnsafeMutableRawPointer) -> RawEntry? {
        var field = start
        let returned = field.loadUnaligned(as: attribute_set_t.self)
        field += MemoryLayout<attribute_set_t>.size

        guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else { return nil }
        let nameRef = field.loadUnaligned(as: attrreference_t.self)
        let nameStart = field + Int(nameRef.attr_dataoffset)
        let nameLength = max(0, Int(nameRef.attr_length) - 1) // sans le NUL final
        let name = String(decoding: UnsafeRawBufferPointer(start: nameStart, count: nameLength), as: UTF8.self)
        field += MemoryLayout<attrreference_t>.size
        // Garde-fou : un nom invalide ferait relire le dossier parent à l'infini.
        guard !name.isEmpty, name != ".", name != "..", !name.utf8.contains(0), !name.utf8.contains(0x2F) else {
            return nil
        }

        var objType: fsobj_type_t = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
            objType = field.loadUnaligned(as: fsobj_type_t.self)
            field += MemoryLayout<fsobj_type_t>.size
        }
        var modTime = timespec()
        if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
            modTime = field.loadUnaligned(as: timespec.self)
            field += MemoryLayout<timespec>.size
        }
        var fileID: UInt64 = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
            fileID = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }
        var linkCount: UInt32 = 1
        if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
            linkCount = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }
        var allocSize: off_t = 0
        if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
            allocSize = field.loadUnaligned(as: off_t.self)
            field += MemoryLayout<off_t>.size
        }

        let kind: RawEntry.Kind
        switch objType {
        case fsobj_type_t(VREG.rawValue): kind = .file
        case fsobj_type_t(VDIR.rawValue): kind = .directory
        case fsobj_type_t(VLNK.rawValue): kind = .symlink
        default: kind = .other
        }

        return RawEntry(
            name: name,
            kind: kind,
            allocatedSize: kind == .file ? UInt64(max(0, allocSize)) : 0,
            modificationTime: Int64(modTime.tv_sec),
            linkCount: linkCount,
            fileID: fileID
        )
    }
}
