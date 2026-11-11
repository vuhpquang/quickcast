import SwiftUI

/// The list beside the selected dictation's full text and details.
struct DictationHistoryBrowser: View {
    @Environment(\.metrics) private var metrics
    let results: [DictationHistoryEntry]
    let selected: DictationHistoryEntry?
    let scroll: ScrollIntent
    let onSelect: (DictationHistoryEntry) -> Void
    let onActivate: () -> Void
    let onActions: (DictationHistoryEntry) -> Void

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: metrics.size.clipboardListWidth)
            Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
            DictationHistoryPreview(entry: selected)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results, id: \.id.uuidString) { entry in
                        DictationHistoryRow(entry: entry, selected: entry.id == selected?.id)
                            .selectionFrame(entry.id == selected?.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(entry) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(entry)
                                    onActivate()
                                }
                            )
                            .onRightClick { onActions(entry) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selected?.id.uuidString,
                atOrigin: selected != nil && selected?.id == results.first?.id, proxy: proxy)
        }
    }
}

private struct DictationHistoryRow: View {
    @Environment(\.metrics) private var metrics
    let entry: DictationHistoryEntry
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        IconCache.observeStyle()
        return HStack(spacing: metrics.spacing.lg) {
            Image(nsImage: IconCache.symbolIcon(named: "waveform")).resizable()
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                .accessibilityHidden(true)
            Text(entry.preview)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.lg)
            Text(entry.date, format: .relative(presentation: .named))
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct DictationHistoryPreview: View {
    @Environment(\.metrics) private var metrics
    let entry: DictationHistoryEntry?

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    Text(entry.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                DictationHistoryInfo(entry: entry)
            }
            .padding(.horizontal, metrics.spacing.lg)
        } else {
            Color.clear
        }
    }
}

/// Everything shown here was saved with the entry, so nothing is looked up per arrow key.
private struct DictationHistoryInfo: View {
    @Environment(\.metrics) private var metrics
    let entry: DictationHistoryEntry

    private var rows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let appName = entry.appName {
            rows.append((String(localized: "Application"), appName))
        }
        rows.append((String(localized: "Model"), entry.modelTitle))
        rows.append(
            (String(localized: "Date"), entry.date.formatted(date: .abbreviated, time: .shortened)))
        rows.append((String(localized: "Words"), entry.wordCount.formatted()))
        rows.append((String(localized: "Characters"), entry.text.count.formatted()))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Information")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    HStack(spacing: metrics.spacing.sm) {
                        Text(rows[index].label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(rows[index].value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
    }
}
