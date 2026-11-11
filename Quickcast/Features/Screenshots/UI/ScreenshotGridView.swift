import SwiftUI

/// One grid row of cells; `start` is its first cell's flat selection index.
private struct ScreenshotGridRow: Identifiable {
    let id: String
    let start: Int
    let items: ArraySlice<Screenshot>
    let isLastInDay: Bool

    subscript(column: Int) -> Screenshot {
        items[items.index(items.startIndex, offsetBy: column)]
    }
}

private enum ScreenshotGridItem: Identifiable {
    case header(id: String, day: Date, count: Int)
    case row(ScreenshotGridRow)

    var id: String {
        switch self {
        case .header(let id, _, _): return id
        case .row(let row): return row.id
        }
    }
}

/// The emoji grid's structure, for the reasons in docs/features/emoji.md#rendering: rows sit
/// directly under the lazy stack as scroll targets, and interaction lives on the row.
struct ScreenshotGridView: View {
    @Environment(\.metrics) private var metrics
    let days: [ScreenshotDay]
    let selection: Int
    let columns: ScreenshotGridColumns
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    private var items: [ScreenshotGridItem] {
        var items: [ScreenshotGridItem] = []
        for day in days {
            let dayID = String(Int(day.day.timeIntervalSinceReferenceDate))
            items.append(.header(id: dayID + "-header", day: day.day, count: day.items.count))
            var offset = 0
            var row = 0
            while offset < day.items.count {
                let end = min(offset + columns.rawValue, day.items.count)
                items.append(
                    .row(
                        ScreenshotGridRow(
                            id: dayID + "-row-\(row)", start: day.start + offset,
                            items: day.items[offset..<end], isLastInDay: end == day.items.count)))
                offset = end
                row += 1
            }
        }
        return items
    }

    private var selectedRowID: String? {
        guard let day = days.last(where: { selection >= $0.start }),
            selection - day.start < day.items.count
        else { return nil }
        return String(Int(day.day.timeIntervalSinceReferenceDate))
            + "-row-\((selection - day.start) / columns.rawValue)"
    }

    private var firstRowID: String? {
        days.first.map { String(Int($0.day.timeIntervalSinceReferenceDate)) + "-row-0" }
    }

    var body: some View {
        let items = items
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .header(_, let day, let count):
                            ScreenshotDayHeader(day: day, count: count, isFirst: item.id == items.first?.id)
                        case .row(let row):
                            ScreenshotGridRowView(
                                row: row, selection: selection, columns: columns,
                                onSelect: onSelect, onActivate: onActivate, onActions: onActions
                            )
                            .padding(.bottom, row.isLastInDay ? 0 : metrics.spacing.md)
                            .selectionFrame(item.id == selectedRowID)
                        }
                    }
                }
                .padding(.horizontal, metrics.size.emojiGridInset)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: selectedRowID == firstRowID, proxy: proxy)
        }
    }
}

private struct ScreenshotDayHeader: View {
    @Environment(\.metrics) private var metrics
    let day: Date
    let count: Int
    let isFirst: Bool

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return sameYear
            ? day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            : day.formatted(.dateTime.day().month(.wide).year())
    }

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(title)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(count, format: .number)
                .foregroundStyle(Theme.Colors.textTertiary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .font(metrics.typography.sectionHeader)
        .padding(.top, isFirst ? metrics.spacing.xs : metrics.spacing.emojiSectionSpacing)
        .padding(.bottom, metrics.spacing.md)
        .accessibilityElement(children: .combine)
    }
}

/// One row, owning all interaction for its cells, as `EmojiGridRowView` does.
private struct ScreenshotGridRowView: View {
    @Environment(\.metrics) private var metrics
    @Environment(PaletteState.self) private var palette
    let row: ScreenshotGridRow
    let selection: Int
    let columns: ScreenshotGridColumns
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    @State private var hoveredColumn: Int?

    private var spacing: CGFloat { metrics.spacing.md }

    /// The palette has a fixed metric width, so cells are sized without a measuring pass.
    private var cellWidth: CGFloat {
        let count = CGFloat(columns.rawValue)
        let contentWidth = metrics.size.panelWidth - metrics.size.emojiGridInset * 2
        return (contentWidth - spacing * (count - 1)) / count
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns.rawValue, id: \.self) { column in
                if column < row.items.count {
                    ScreenshotCell(
                        item: row[column], selected: row.start + column == selection,
                        hovered: column == hoveredColumn, width: cellWidth)
                } else {
                    Color.clear.frame(width: cellWidth, height: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                if let column = column(at: value.location) { onSelect(row.start + column) }
            }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { value in
                guard let column = column(at: value.location) else { return }
                onSelect(row.start + column)
                onActivate()
            }
        )
        .onRightClick { point in
            if let column = column(at: point) { onActions(row.start + column) }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                hoveredColumn = palette.hoverHighlightArmed ? column(at: point) : nil
            case .ended:
                hoveredColumn = nil
            }
        }
        .onChange(of: palette.hoverDisarmToken) { hoveredColumn = nil }
    }

    private func column(at point: CGPoint) -> Int? {
        guard point.x >= 0 else { return nil }
        let pitch = cellWidth + spacing
        let column = Int(point.x / pitch)
        let positionInCell = point.x - CGFloat(column) * pitch
        guard column < row.items.count, positionInCell <= cellWidth else { return nil }
        return column
    }
}

/// Pure content: the tile and its caption, no gestures or hover tracking of its own.
private struct ScreenshotCell: View {
    @Environment(\.metrics) private var metrics
    let item: Screenshot
    let selected: Bool
    let hovered: Bool
    let width: CGFloat

    /// Most captures are a window or a display, so a 16:10 tile wastes the least room.
    private var tileHeight: CGFloat { (width * 10 / 16).rounded() }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Theme.Colors.emojiCell
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.emojiCell, style: .continuous)
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            ZStack {
                shape.fill(fill)
                ScreenshotTile(
                    url: item.url, kind: item.kind, points: width,
                    cornerRadius: max(metrics.radius.emojiCell - metrics.spacing.sm, 0)
                )
                .padding(metrics.spacing.sm)
                if selected {
                    shape.strokeBorder(Theme.Colors.emojiSelectionBorder, lineWidth: 2)
                    shape.inset(by: 2).strokeBorder(Theme.Colors.emojiInnerBorder, lineWidth: 1)
                } else if hovered {
                    shape.strokeBorder(Theme.Colors.emojiHoverBorder, lineWidth: 2)
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: tileHeight)
            .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
            HStack(spacing: metrics.spacing.xs) {
                if item.kind == .recording {
                    Image(systemName: "video.fill").accessibilityHidden(true)
                }
                Text(item.date, format: .dateTime.hour().minute())
                    .monospacedDigit()
            }
            .font(metrics.typography.keyCap)
            .foregroundStyle(selected ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, metrics.spacing.xs)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Generated off-main on first sight; a tile scrolled away cancels its request.
private struct ScreenshotTile: View {
    let url: URL
    let kind: Screenshot.Kind
    let points: CGFloat
    let cornerRadius: CGFloat

    @State private var image: NSImage?

    private var maxPixel: CGFloat { ScreenshotThumbnails.pixelSize(forPoints: points) }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                Image(systemName: kind == .recording ? "video" : "photo")
                    .font(.title2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            if let hit = ScreenshotThumbnails.cached(url, maxPixel: maxPixel) {
                image = hit
                return
            }
            image = nil
            image = await ScreenshotThumbnails.load(url, maxPixel: maxPixel)
        }
    }
}
