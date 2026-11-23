import StorageCore
import SwiftUI

/// Légende des couleurs du treemap.
struct LegendView: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(ContentKind.allCases, id: \.self) { kind in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(kind.color).frame(width: 10, height: 10)
                    Text(kind.label).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
