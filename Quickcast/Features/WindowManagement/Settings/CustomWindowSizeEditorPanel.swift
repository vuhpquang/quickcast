import AppKit
import SwiftUI

/// Identifies the editor to present; nil is "new", and the UUID keeps two opens distinct.
struct CustomWindowSizeEditRequest: Identifiable {
    let id = UUID()
    var size: CustomWindowSize?
}

struct CustomWindowSizeEditorPanel: View {
    private let isNew: Bool
    /// What a unit switch converts against; a run measures the window's own display.
    private let reference: CGSize

    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(CustomWindowSizeCoordinator.self) private var coordinator
    @State private var size: CustomWindowSize
    @State private var errorMessage: String?

    init(request: CustomWindowSizeEditRequest) {
        isNew = request.size == nil
        reference = NSScreen.main?.visibleFrame.size ?? .zero
        _size = State(initialValue: request.size ?? CustomWindowSize(name: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: isNew ? "New Custom Size" : "Edit Custom Size",
                subtitle: "Sizes or moves the window you were last in, on the display it is already on.")

            field("Name") {
                TextField("Wide Center", text: $size.name)
                    .settingsEditorTextField()
            }

            field("Size") {
                // Quickcast fork: stacked, so three units per length still fit the sheet.
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    dimensionField(
                        label: String(localized: "W"), name: String(localized: "Width"),
                        dimension: $size.width,
                        available: reference.width)
                    dimensionField(
                        label: String(localized: "H"), name: String(localized: "Height"),
                        dimension: $size.height,
                        available: reference.height)
                }
            }

            field("Offset") {
                HStack(spacing: Theme.Spacing.lg) {
                    offsetField(
                        label: "X", name: String(localized: "Horizontal offset"), value: \.x,
                        unit: \.xUnit, available: reference.width)
                    offsetField(
                        label: "Y", name: String(localized: "Vertical offset"), value: \.y,
                        unit: \.yUnit, available: reference.height)
                }
            }

            field("Position") {
                WindowLayoutPositionGrid(selection: size.anchor) { size.anchor = $0 }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.destructive)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    private func field(
        _ title: LocalizedStringResource, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.callout.weight(.medium))
            content()
        }
    }

    private func dimensionField(
        label: String, name: String, dimension: Binding<CustomWindowSize.Dimension>,
        available: CGFloat
    ) -> some View {
        let unit = dimension.wrappedValue.unit
        return HStack(spacing: Theme.Spacing.sm) {
            WindowLayoutNumberField(
                label: label, name: name, suffix: unit.suffix, range: unit.range,
                value: dimension.wrappedValue.value,
                onCommit: { dimension.wrappedValue = .init($0, unit) })
            .disabled(unit == .current)
            Picker(
                "\(name) unit",
                selection: Binding(
                    get: { unit },
                    set: {
                        dimension.wrappedValue = dimension.wrappedValue.converted(
                            to: $0, in: available)
                    })
            ) {
                ForEach(CustomWindowSize.Dimension.Unit.allCases, id: \.self) {
                    Text($0.title).tag($0)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.barControl))
            .fixedSize()
        }
    }

    private func offsetField(
        label: String, name: String, value: WritableKeyPath<CustomWindowSize.Offset, Int>,
        unit: WritableKeyPath<CustomWindowSize.Offset, CustomWindowSize.Offset.Unit>,
        available: CGFloat
    ) -> some View {
        let current = size.offset[keyPath: unit]
        return HStack(spacing: Theme.Spacing.sm) {
            WindowLayoutNumberField(
                label: label, name: name, suffix: current.suffix, range: current.range,
                value: size.offset[keyPath: value],
                onCommit: { size.offset[keyPath: value] = $0 })
            // Quickcast fork: a share of the display, converted like a length's unit switch.
            Picker(
                "\(name) unit",
                selection: Binding(
                    get: { current },
                    set: { size.offset = Self.offset(size.offset, value, unit, to: $0, in: available) })
            ) {
                ForEach(CustomWindowSize.Offset.Unit.allCases, id: \.self) {
                    Text($0.suffix).tag($0)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.barControl))
            .fixedSize()
        }
    }

    private static func offset(
        _ offset: CustomWindowSize.Offset, _ value: WritableKeyPath<CustomWindowSize.Offset, Int>,
        _ unit: WritableKeyPath<CustomWindowSize.Offset, CustomWindowSize.Offset.Unit>,
        to target: CustomWindowSize.Offset.Unit, in available: CGFloat
    ) -> CustomWindowSize.Offset {
        var converted = offset
        let number = CGFloat(offset[keyPath: value])
        if available > 0, offset[keyPath: unit] != target {
            let scaled = target == .percent ? number / available * 100 : number * available / 100
            converted[keyPath: value] = Int(scaled.rounded())
        }
        converted[keyPath: unit] = target
        // Re-clamped through the initializer, so a converted value lands inside its new range.
        return CustomWindowSize.Offset(
            x: converted.x, y: converted.y, xUnit: converted.xUnit, yUnit: converted.yUnit)
    }

    private var canSave: Bool {
        !size.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        do {
            try coordinator.saveCustomWindowSize(size)
            dismiss()
        } catch {
            errorMessage = error.errorDescription
        }
    }
}
