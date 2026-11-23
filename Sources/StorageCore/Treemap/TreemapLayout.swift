import CoreGraphics

/// Algorithme « squarified » (Bruls, Huizing, van Wijk) : découpe un rectangle
/// en sous-rectangles d'aires proportionnelles aux tailles, aussi carrés que possible.
public enum TreemapLayout {
    /// - Parameter sizes: tailles, idéalement triées par ordre décroissant.
    /// - Returns: un rectangle par taille, dans le même ordre. Une taille nulle donne un rectangle vide.
    public static func squarify(sizes: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: sizes.count)
        let total = sizes.reduce(0) { $0 + max(0, $1) }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        let scale = Double(rect.width * rect.height) / total
        let areas = sizes.map { max(0, $0) * scale }
        var remaining = rect
        var start = 0

        while start < areas.count {
            if areas[start] <= 0 {
                result[start] = CGRect(origin: remaining.origin, size: .zero)
                start += 1
                continue
            }
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var rowSum = areas[start]
            var rowMin = areas[start]
            var rowMax = areas[start]
            while end < areas.count, areas[end] > 0 {
                let candidate = areas[end]
                let current = worst(sum: rowSum, min: rowMin, max: rowMax, side: side)
                let next = worst(sum: rowSum + candidate, min: min(rowMin, candidate),
                                 max: max(rowMax, candidate), side: side)
                guard next <= current else { break }
                rowSum += candidate
                rowMin = min(rowMin, candidate)
                rowMax = max(rowMax, candidate)
                end += 1
            }
            remaining = place(row: start..<end, areas: areas, sum: rowSum, in: remaining, into: &result)
            start = end
        }
        return result
    }

    /// Pire rapport d'aspect d'une rangée posée le long d'un côté de longueur `side`.
    private static func worst(sum: Double, min: Double, max: Double, side: Double) -> Double {
        let s2 = side * side
        let sum2 = sum * sum
        return Swift.max(s2 * max / sum2, sum2 / (s2 * min))
    }

    /// Pose la rangée le long du plus petit côté et renvoie l'espace restant.
    private static func place(row: Range<Int>, areas: [Double], sum: Double,
                              in rect: CGRect, into result: inout [CGRect]) -> CGRect {
        if rect.width >= rect.height {
            // Colonne verticale à gauche.
            let width = CGFloat(sum) / rect.height
            var y = rect.minY
            for i in row {
                let height = CGFloat(areas[i]) / width
                result[i] = CGRect(x: rect.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: rect.minX + width, y: rect.minY, width: max(0, rect.width - width), height: rect.height)
        } else {
            // Rangée horizontale en haut.
            let height = CGFloat(sum) / rect.width
            var x = rect.minX
            for i in row {
                let width = CGFloat(areas[i]) / height
                result[i] = CGRect(x: x, y: rect.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: max(0, rect.height - height))
        }
    }
}
