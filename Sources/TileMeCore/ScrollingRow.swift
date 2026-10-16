import CoreGraphics

/// A horizontal strip in logical coordinates. Focus changes the viewport, never neighboring widths.
public struct ScrollingRow: Sendable {
    public struct Column: Equatable, Sendable {
        public let id: Int
        public var width: CGFloat
        public init(id: Int, width: CGFloat) { self.id = id; self.width = width }
    }
    public private(set) var columns: [Column] = []
    public private(set) var focusedID: Int?
    public private(set) var offset: CGFloat = 0
    public init() {}

    public mutating func insert(id: Int, width: CGFloat) {
        guard !columns.contains(where: { $0.id == id }) else { return }
        let index = focusedID.flatMap { focus in columns.firstIndex { $0.id == focus } }.map { $0 + 1 } ?? columns.count
        columns.insert(Column(id: id, width: max(1, width.isFinite ? width : 600)), at: index)
        focusedID = id
    }
    public mutating func remove(id: Int) {
        guard let index = columns.firstIndex(where: { $0.id == id }) else { return }
        columns.remove(at: index)
        if focusedID == id { focusedID = columns.isEmpty ? nil : columns[min(index, columns.count - 1)].id }
    }
    public mutating func focus(id: Int) {
        if columns.contains(where: { $0.id == id }) { focusedID = id }
    }
    @discardableResult public mutating func step(_ direction: Int) -> Int? {
        guard let index = columns.firstIndex(where: { $0.id == focusedID }) else { return nil }
        let next = min(max(index + direction, 0), columns.count - 1)
        focusedID = columns[next].id
        return focusedID
    }
    public mutating func resize(id: Int, width: CGFloat) {
        guard width.isFinite, width > 0, let index = columns.firstIndex(where: { $0.id == id }) else { return }
        columns[index].width = width
    }
    public mutating func layout(in viewport: CGRect, gap: CGFloat = 12) -> [Int: CGRect] {
        let spacing = max(0, gap.isFinite ? gap : 0)
        var starts: [Int: CGFloat] = [:]
        var cursor: CGFloat = 0
        for column in columns {
            starts[column.id] = cursor
            cursor += column.width + spacing
        }
        let total = max(0, cursor - spacing)
        if let focus = columns.first(where: { $0.id == focusedID }), let start = starts[focus.id] {
            if start < offset { offset = start }
            if start + focus.width > offset + viewport.width { offset = start + focus.width - viewport.width }
            if focus.width > viewport.width { offset = start }
        }
        offset = min(max(0, offset), max(0, total - viewport.width))
        return Dictionary(uniqueKeysWithValues: columns.map { column in
            (column.id, CGRect(x: viewport.minX + starts[column.id]! - offset, y: viewport.minY,
                               width: column.width, height: viewport.height))
        })
    }
}
