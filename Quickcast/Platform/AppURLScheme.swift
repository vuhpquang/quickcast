import Foundation

/// This channel's own link scheme: `quickcast`, or `quickcast-dev` for Debug. Set in project.yml.
enum AppURLScheme {
    static let current: String = {
        guard let scheme = Bundle.main.object(forInfoDictionaryKey: "QuickcastURLScheme") as? String
        else { preconditionFailure("Info.plist must name QuickcastURLScheme") }
        return scheme
    }()
}
