import Foundation

/// Quickcast fork: Move Window, the one command that takes typed input.
extension WindowCommandCoordinator {
    /// Missing or out-of-range values open the row's fields, as a custom command's do.
    func runMoveWindow(values: [String: String]) {
        guard settings.windowManagementEnabled else { return }
        typealias Field = CustomWindowSize.MoveField
        guard
            let move = CustomWindowSize.move(
                x: values[Field.x], y: values[Field.y], anchor: values[Field.anchor])
        else {
            guard let command = WindowCommandCatalog.command(id: .moveWindow) else { return }
            paletteCoordinator.showArguments(of: AppEntry(command), values: values)
            return
        }
        runWindowSize(move)
    }
}
