import Foundation
import SwiftUI
import StorageCore

/// Mise en forme des valeurs affichées (suit la langue du système).
enum Format {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    static func scanDate(_ date: Date) -> String {
        "Scan du " + date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    static func percent(_ part: UInt64, of total: UInt64) -> String {
        guard total > 0 else { return "–" }
        return (Double(part) / Double(total)).formatted(.percent.precision(.fractionLength(0...1)))
    }
}

extension ContentKind {
    /// Couleur du treemap et de la légende.
    var color: Color {
        switch self {
        case .video: Color(red: 0.94, green: 0.38, blue: 0.38)
        case .image: Color(red: 0.98, green: 0.62, blue: 0.22)
        case .audio: Color(red: 0.93, green: 0.80, blue: 0.27)
        case .code: Color(red: 0.32, green: 0.78, blue: 0.55)
        case .app: Color(red: 0.38, green: 0.56, blue: 0.98)
        case .archive: Color(red: 0.63, green: 0.47, blue: 0.95)
        case .document: Color(red: 0.27, green: 0.75, blue: 0.85)
        case .system: Color(red: 0.56, green: 0.59, blue: 0.65)
        case .other: Color(red: 0.73, green: 0.75, blue: 0.79)
        }
    }
}
