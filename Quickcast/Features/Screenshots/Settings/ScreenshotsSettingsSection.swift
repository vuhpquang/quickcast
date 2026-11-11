import SwiftUI

/// Search Screenshots' command row, grid density and text search, inside the File Search pane.
struct ScreenshotsSettingsSection: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Section {
            ForEach(
                CommandCatalog.entries(ownedBy: .fileSearch).filter {
                    $0.id == CommandID.searchScreenshots.rawValue
                }
            ) { FeatureCommandRow(entry: $0) }
            Picker(selection: $settings.screenshotGridColumns) {
                ForEach(ScreenshotGridColumns.allCases) { columns in
                    Text(columns.rawValue, format: .number).tag(columns)
                }
            } label: {
                SettingsRowTitle(.fileSearchScreenshots, "Column Count")
                Text("⌘+ and ⌘- change it until the screen closes.")
            }
            Toggle(isOn: $settings.screenshotTextSearchEnabled) {
                SettingsRowTitle(.fileSearchScreenshots, "Search text in screenshots")
                Text("Recognizes text on this Mac while Search Screenshots is open.")
            }
            LabeledContent {
                Text(verbatim: core.screenshotsCoordinator.library.folder.path(percentEncoded: false))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            } label: {
                SettingsRowTitle(.fileSearchScreenshots, "Folder")
                Text("Change it in the Screenshot app’s Options menu.")
            }
        } header: {
            SettingsSectionHeader(.fileSearchScreenshots)
        } footer: {
            Text("Screenshots and screen recordings are read where macOS saves them, never copied.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
