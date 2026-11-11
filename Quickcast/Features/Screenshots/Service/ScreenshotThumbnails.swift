import AppKit
import QuickLookThumbnailing

/// Quick Look tiles for the grid, in their own cache so they never evict clipboard previews.
enum ScreenshotThumbnails {
    private static let cache = ThumbnailCache(rowBytes: 0, previewBytes: 48 * 1024 * 1024)

    /// Tiles are requested in steps, so a zoom reuses a sharper tile rather than missing the cache.
    static func pixelSize(forPoints points: CGFloat) -> CGFloat {
        max(160, (points / 80).rounded(.up) * 80)
    }

    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.cached(url, maxPixel: maxPixel)
    }

    /// Called when the screen closes; Quick Look keeps its own disk cache for the next open.
    static func purge() {
        cache.purgePreviews()
    }

    static func load(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: maxPixel, height: maxPixel), scale: 2,
            representationTypes: .thumbnail)
        guard !Task.isCancelled,
            let rendered = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }
        let cgImage = rendered.cgImage
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.store(image, for: url, maxPixel: maxPixel, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
