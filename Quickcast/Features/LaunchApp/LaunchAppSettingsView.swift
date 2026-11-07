import SwiftUI

struct LaunchAppSettingsView: View {
    var body: some View {
        Form {
            FeatureCommandsSection(owner: .launchApp, anchor: .launchAppCommands)

            Section {
                if let url = LaunchAppBridge.appURL {
                    LabeledContent {
                        Button("Open") { LaunchAppBridge.open() }
                    } label: {
                        Text("Installed")
                        Text(url.path)
                    }
                } else {
                    LabeledContent {
                        Button("Download…") { NSWorkspace.shared.open(LaunchAppBridge.releasesURL) }
                    } label: {
                        Text("Not installed")
                        Text("Open LaunchApp needs LaunchApp in Applications.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
