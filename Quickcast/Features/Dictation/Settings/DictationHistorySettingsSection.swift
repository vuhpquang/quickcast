import SwiftUI

/// How many finished dictations Dictation History keeps, and the one way to drop them all.
struct DictationHistorySettingsSection: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var confirmingClear = false

    var body: some View {
        @Bindable var settings = settings
        let store = core.dictationHistoryCoordinator.store
        return Section {
            Picker(selection: $settings.dictationHistoryLimit) {
                ForEach(DictationHistoryLimit.allCases) { limit in
                    Text(verbatim: limit.title(locale: .current)).tag(limit)
                }
            } label: {
                SettingsRowTitle(.dictationHistory, "Keep recent dictations")
                Text("Turning it off deletes the saved dictations.")
            }
            LabeledContent {
                Button("Clear History…") { confirmingClear = true }
                    .disabled(store.entries.isEmpty)
            } label: {
                Text("\(store.entries.count) saved dictations")
            }
        } header: {
            SettingsSectionHeader(.dictationHistory)
        } footer: {
            Text("Dictation history stays on this Mac and is never sent anywhere.")
        }
        .confirmationDialog(
            "Clear dictation history?", isPresented: $confirmingClear, titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) { store.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every saved dictation is deleted from this Mac. This can't be undone.")
        }
    }
}
