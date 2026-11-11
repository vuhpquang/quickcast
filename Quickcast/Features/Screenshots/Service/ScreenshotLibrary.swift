import CoreServices
import Foundation

/// The captures in the macOS screenshot folder, rescanned off-main and watched while shown.
@MainActor
@Observable
final class ScreenshotLibrary {
    enum State: Equatable {
        case loading
        case loaded
        /// The folder is missing, or privacy settings keep Quickcast out of it.
        case unreadable
    }

    private(set) var items: [Screenshot] = []
    private(set) var state: State = .loading
    private(set) var folder: URL
    /// Bumped whenever `items` changes, so memos and the selection can follow it.
    private(set) var revision = 0

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: FileSystemWatcher?
    @ObservationIgnored private let watchQueue = DispatchQueue(
        label: "com.vuhpquang.quickcast.screenshots", qos: .utility)

    init() {
        folder = Self.configuredFolder()
    }

    /// Re-reads the screenshot settings each time, since the Screenshot app can move the folder.
    func activate() {
        let configured = Self.configuredFolder()
        if configured != folder {
            folder = configured
            watcher = nil
            items = []
            state = .loading
            revision += 1
        }
        if watcher == nil {
            watcher = FileSystemWatcher(
                paths: [folder.path], since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                queue: watchQueue
            ) { [weak self] _ in
                Task { @MainActor in self?.rescan() }
            }
        }
        rescan()
    }

    func deactivate() {
        watcher = nil
        scanTask?.cancel()
        scanTask = nil
    }

    func rescan() {
        scanTask?.cancel()
        let folder = folder
        let prefix = Self.customPrefix()
        scanTask = Task { [weak self] in
            let scanned = await Self.scan(folder, customPrefix: prefix)
            guard !Task.isCancelled, let self, self.folder == folder else { return }
            self.apply(scanned)
        }
    }

    /// Takes the row out at once; the watcher's rescan then agrees with it.
    func remove(_ item: Screenshot) {
        guard let index = items.firstIndex(of: item) else { return }
        items.remove(at: index)
        revision += 1
    }

    private func apply(_ scanned: [Screenshot]?) {
        guard let scanned else {
            if state != .unreadable || !items.isEmpty {
                items = []
                state = .unreadable
                revision += 1
            }
            return
        }
        let sorted = ScreenshotGrid.sorted(scanned)
        guard sorted != items || state != .loaded else { return }
        items = sorted
        state = .loaded
        revision += 1
    }

    private static func configuredFolder() -> URL {
        let location = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString)
        return ScreenshotDetection.folder(
            configured: location as? String, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    private static func customPrefix() -> String? {
        CFPreferencesCopyAppValue("name" as CFString, "com.apple.screencapture" as CFString) as? String
    }

    /// Nil when the folder can't be listed. One level only: captures never land in subfolders.
    @concurrent
    private nonisolated static func scan(_ folder: URL, customPrefix: String?) async -> [Screenshot]? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
        else { return nil }
        var found: [Screenshot] = []
        for url in urls {
            if Task.isCancelled { return nil }
            // The extension is checked first, so only candidate files pay for the xattr read.
            guard ScreenshotDetection.kind(ofPathExtension: url.pathExtension) != nil,
                let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                let kind = ScreenshotDetection.kind(
                    of: url.lastPathComponent, flaggedAsCapture: isFlaggedCapture(url),
                    customPrefix: customPrefix)
            else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            found.append(
                Screenshot(url: url, date: values.creationDate ?? modified, modified: modified, kind: kind))
        }
        return found
    }

    /// `screencapture` stamps this Spotlight attribute on the file itself, as a binary plist bool.
    private nonisolated static func isFlaggedCapture(_ url: URL) -> Bool {
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        return url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0, size < 1024 else { return false }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            guard read == size,
                let value = try? PropertyListSerialization.propertyList(from: data, format: nil)
            else { return false }
            return (value as? NSNumber)?.boolValue ?? false
        }
    }
}
