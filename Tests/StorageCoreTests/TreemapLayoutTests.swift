import CoreGraphics
import Testing
@testable import StorageCore

private func area(_ r: CGRect) -> Double { Double(r.width * r.height) }

@Suite struct TreemapLayoutTests {
    let bounds = CGRect(x: 10, y: 20, width: 600, height: 400)

    @Test func emptyAndZeroInputsGiveEmptyRects() {
        #expect(TreemapLayout.squarify(sizes: [], in: bounds).isEmpty)
        #expect(TreemapLayout.squarify(sizes: [0, 0], in: bounds).allSatisfy { $0.isEmpty })
        #expect(TreemapLayout.squarify(sizes: [5], in: .zero) == [.zero])
    }

    @Test func singleItemFillsTheRect() {
        let rects = TreemapLayout.squarify(sizes: [42], in: bounds)
        #expect(rects.count == 1)
        #expect(abs(area(rects[0]) - area(bounds)) < 0.5)
        #expect(rects[0].minX == bounds.minX && rects[0].minY == bounds.minY)
    }

    static let cases: [[Double]] = [
        [6, 6, 4, 3, 2, 2, 1],
        [1000, 1, 1, 1],
        [50, 30, 20],
        Array(repeating: 1, count: 37),
    ]

    @Test(arguments: TreemapLayoutTests.cases)
    func rectsAreProportionalInsideAndDisjoint(sizes: [Double]) {
        let rects = TreemapLayout.squarify(sizes: sizes, in: bounds)
        let total = sizes.reduce(0, +)
        #expect(rects.count == sizes.count)

        let covered = rects.map(area).reduce(0, +)
        #expect(abs(covered - area(bounds)) / area(bounds) < 0.001)

        for (size, rect) in zip(sizes, rects) {
            let expected = size / total * area(bounds)
            #expect(abs(area(rect) - expected) / expected < 0.01)
            #expect(rect.minX >= bounds.minX - 0.01 && rect.maxX <= bounds.maxX + 0.01)
            #expect(rect.minY >= bounds.minY - 0.01 && rect.maxY <= bounds.maxY + 0.01)
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || area(overlap) < 0.01)
            }
        }
    }

    @Test func equalSizesInASquareGiveSquares() {
        let rects = TreemapLayout.squarify(sizes: [1, 1, 1, 1], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        for r in rects {
            #expect(abs(r.width - 50) < 0.01)
            #expect(abs(r.height - 50) < 0.01)
        }
    }

    @Test func zeroSizesAtTheEndGetEmptyRects() {
        let rects = TreemapLayout.squarify(sizes: [10, 5, 0], in: bounds)
        #expect(rects[2].isEmpty)
        #expect(abs(area(rects[0]) + area(rects[1]) - area(bounds)) < 0.5)
    }
}
