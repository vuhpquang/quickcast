import Foundation

/// One capture in the screenshot folder; the path is its identity, so a rename is a new item.
struct Screenshot: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case image
        case recording
    }

    let url: URL
    /// When it was taken: the file's creation date, which a later edit does not move.
    let date: Date
    /// Keys the recognized-text cache, so an edited capture is read again.
    let modified: Date
    let kind: Kind

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

/// Which files in the folder are captures, and where the folder is.
enum ScreenshotDetection {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif"]
    static let recordingExtensions: Set<String> = ["mov", "mp4"]

    /// The names `screencapture` gives in the languages Quickcast ships, plus pre-Mojave English.
    static let defaultPrefixes: [String] = [
        "Screenshot", "Screen Shot", "Screen Recording",
        "Ảnh màn hình", "Bản ghi màn hình",
        "Bildschirmfoto", "Bildschirmaufnahme",
        "Capture d’écran", "Capture d'écran", "Enregistrement de l’écran",
        "Captura de pantalla", "Grabación de pantalla",
        "Captura de Tela", "Gravação de Tela",
        "スクリーンショット", "画面収録",
        "스크린샷", "화면 기록",
        "截屏", "屏幕录制",
        "Снимок экрана", "Запись экрана"
    ].map(fold)

    static func kind(ofPathExtension pathExtension: String) -> Screenshot.Kind? {
        let ext = pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if recordingExtensions.contains(ext) { return .recording }
        return nil
    }

    /// The capture flag `screencapture` writes wins; a name is the fallback for copies that lost it.
    static func kind(
        of fileName: String, flaggedAsCapture: Bool, customPrefix: String? = nil
    ) -> Screenshot.Kind? {
        guard let kind = kind(ofPathExtension: (fileName as NSString).pathExtension) else { return nil }
        if flaggedAsCapture { return kind }
        let folded = fold(fileName)
        var prefixes = defaultPrefixes
        if let customPrefix, !customPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
            prefixes.append(fold(customPrefix))
        }
        return prefixes.contains(where: folded.hasPrefix) ? kind : nil
    }

    /// `com.apple.screencapture`'s `location`, `~` expanded; unset or blank means the Desktop.
    static func folder(configured: String?, home: URL) -> URL {
        let raw = configured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return home.appending(path: "Desktop", directoryHint: .isDirectory) }
        let path: String
        if raw == "~" {
            path = home.path
        } else if raw.hasPrefix("~/") {
            path = home.path + raw.dropFirst()
        } else if raw.hasPrefix("/") {
            path = raw
        } else {
            path = home.appending(path: raw).path
        }
        return URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
    }
}
