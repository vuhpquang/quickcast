import SwiftUI

/// Quickcast fork: Move Window's X and Y fields in root search, as a custom command's are.
@MainActor
enum MoveWindowArgumentsAccessory {
    private static let arguments = [
        InlineArgument(id: CustomWindowSize.MoveField.x, title: "X"),
        InlineArgument(id: CustomWindowSize.MoveField.y, title: "Y")
    ]

    static func make(
        entry: AppEntry, vm: PaletteState, metrics: InterfaceMetrics,
        focus: FocusState<String?>.Binding, onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard let command = WindowCommandCatalog.command(forEntryID: entry.id),
            command.id == .moveWindow
        else { return nil }
        let value = { (id: String) in binding(entryID: entry.id, id: id, vm: vm) }
        let firstOwed = { arguments.first { value($0.id).wrappedValue.isEmpty }?.id }
        return PaletteHeaderAccessory(
            width: InlineArgumentFields.totalWidth(for: arguments, hasIcon: true, metrics: metrics),
            fieldNames: arguments.map(\.id),
            firstIncompleteField: firstOwed(),
            view: AnyView(
                InlineArgumentFields(
                    arguments: arguments, symbol: command.sfSymbol, value: value, focused: focus,
                    openOptions: { _ in },
                    onSubmit: {
                        guard let owed = firstOwed() else { return onSubmit() }
                        focus.wrappedValue = owed
                    }
                )
                .id(entry.id))
        )
    }

    /// The typed values keyed by field, stripped of blanks — what the run funnel is handed.
    static func values(for entry: AppEntry, vm: PaletteState) -> [String: String] {
        var values: [String: String] = [:]
        for argument in arguments {
            let typed = vm.commandArguments[PaletteState.argumentKey(entry.id, argument.id)] ?? ""
            if !typed.isEmpty { values[argument.id] = typed }
        }
        return values
    }

    private static func binding(entryID: String, id: String, vm: PaletteState) -> Binding<String> {
        let key = PaletteState.argumentKey(entryID, id)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }
}
