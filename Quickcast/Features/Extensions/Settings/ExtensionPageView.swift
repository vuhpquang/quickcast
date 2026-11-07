import SwiftUI

/// Quickcast fork: one installed extension's page, reached from its own row in the sidebar.
struct ExtensionPageView: View {
    @Environment(AppCore.self) private var core
    let name: String

    var body: some View {
        if let installed = core.extensions.installed.first(where: { $0.manifest.name == name }) {
            Form {
                Section {
                    header(installed)
                }
                Section {
                    ExtensionSettingsGrid(installed: installed)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "Extension not installed", systemImage: "puzzlepiece.extension",
                description: Text("It may have been uninstalled."))
        }
    }

    private func header(_ installed: InstalledExtension) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: Theme.Size.rowIcon * 2)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(installed.title).font(.title3.weight(.semibold))
                if !installed.manifest.description.isEmpty {
                    Text(installed.manifest.description)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Theme.Spacing.lg)
            if core.extensions.updating.contains(name) {
                ProgressView().controlSize(.small)
            } else if core.extensions.updates[name] != nil {
                Button("Update") { Task { _ = await core.extensions.update([name]) } }
            }
            Button("Uninstall", role: .destructive) {
                core.extensionCoordinator.confirmUninstall(installed)
            }
        }
    }
}

/// The sidebar row for one extension; drawn here so the sidebar never reaches inside one.
struct ExtensionSidebarLabel: View {
    let installed: InstalledExtension

    var body: some View {
        Label {
            Text(installed.title)
        } icon: {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: Theme.Size.rowIcon)
        }
    }
}
