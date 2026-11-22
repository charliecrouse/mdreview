import AppKit
import Markdown

extension MarkdownBuilder {
    struct TableCell {
        let row, column, span, rowSpan: Int
        let content: NSAttributedString
    }

    /// A text table with each column as wide as its widest cell, up to a cap; a table too wide for the
    /// reader shares the measure in proportion instead. Each cell is a paragraph tagged with its row's line.
    mutating func table(_ table: Markdown.Table, _ context: Context) {
        let lines = [line(of: table.head)] + table.body.rows.map { $0.range?.lowerBound.line ?? 1 }
        let cells = cells(of: table, context)
        let columns = max(table.maxColumnCount, 1)
        var widths = [CGFloat](repeating: 40, count: columns)
        for cell in cells where cell.span == 1 && cell.column < columns {
            widths[cell.column] = max(widths[cell.column], min(cell.content.size().width + 18, 320).rounded(.up))
        }
        let total = widths.reduce(0, +)
        let fits = total <= Self.measure - context.indent

        let grid = NSTextTable()
        grid.numberOfColumns = columns
        grid.collapsesBorders = true
        grid.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        for cell in cells {
            let box = NSTextTableBlock(
                table: grid, startingRow: cell.row, rowSpan: cell.rowSpan, startingColumn: cell.column,
                columnSpan: cell.span)
            let width = widths[cell.column..<min(cell.column + cell.span, columns)].reduce(0, +)
            box.setValue(
                fits ? width : width / total * 100, type: fits ? .absoluteValueType : .percentageValueType, for: .width)
            box.setWidth(1, type: .absoluteValueType, for: .border)
            box.setBorderColor(.separatorColor)
            box.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minX)
            box.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxX)
            box.setWidth(4, type: .absoluteValueType, for: .padding, edge: .minY)
            box.setWidth(4, type: .absoluteValueType, for: .padding, edge: .maxY)
            if cell.row == 0 { box.backgroundColor = Self.codeBackground }
            var inner = context
            inner.blocks.append(box)
            inner.indent = 0
            inner.spacing = 0
            let style = style(inner)
            let alignment =
                table.columnAlignments.indices.contains(cell.column) ? table.columnAlignments[cell.column] : nil
            style.alignment = alignment == .center ? .center : alignment == .right ? .right : .natural
            paragraph(cell.content, line: lines[cell.row], inner, style: style)
        }
        separator(line: table.range?.upperBound.line ?? lines[0], context)
    }

    /// The header row, then the body rows. Zero spans mark the cells another cell's span covers.
    private func cells(of table: Markdown.Table, _ context: Context) -> [TableCell] {
        let rows = [Array(table.head.cells)] + table.body.rows.map { Array($0.cells) }
        var cells: [TableCell] = []
        for (row, rowCells) in rows.enumerated() {
            var column = 0
            for cell in rowCells {
                let span = Int(cell.colspan)
                defer { column += max(span, 1) }
                guard span > 0, cell.rowspan > 0 else { continue }
                let font = row == 0 ? NSFont.systemFont(ofSize: bodySize, weight: .semibold) : body
                cells.append(
                    TableCell(
                        row: row, column: column, span: span, rowSpan: Int(cell.rowspan),
                        content: inlines(of: cell, font: font, color: context.color)))
            }
        }
        return cells
    }
}
