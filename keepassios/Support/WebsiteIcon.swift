import Foundation
import LinkPresentation
import UIKit

/// Downloads a website's icon for an entry. Used only when the user has
/// turned on both network access and website icons in Settings.
///
/// LinkPresentation reads the page's declared icons (apple-touch-icon,
/// rel=icon, then /favicon.ico); the result is scaled to 64×64 PNG, the
/// size other KeePass apps use for custom icons, so it stays small in
/// the database file.
nonisolated enum WebsiteIcon {
    static let pixelSize: CGFloat = 64

    /// The URL to ask for, or nil when the entry's URL isn't a website.
    static func pageURL(for entryURL: String) -> URL? {
        let trimmed = entryURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = components.host, !host.isEmpty
        else { return nil }
        return URL(string: "\(scheme)://\(host)")
    }

    /// The entry's URL as a link to open, adding https:// when the user
    /// typed only a host name.
    static func openableURL(for entryURL: String) -> URL? {
        guard pageURL(for: entryURL) != nil else { return nil }
        let trimmed = entryURL.trimmingCharacters(in: .whitespaces)
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }

    /// The icon as PNG data, or nil when the site has none or can't be
    /// reached.
    @concurrent
    static func fetch(for entryURL: String) async -> Data? {
        guard let url = pageURL(for: entryURL) else { return nil }
        let provider = LPMetadataProvider()
        provider.timeout = 10
        guard let metadata = try? await provider.startFetchingMetadata(for: url),
            let iconProvider = metadata.iconProvider
        else { return nil }
        guard let image = await loadImage(from: iconProvider) else { return nil }
        return scaledPNG(image)
    }

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    private static func scaledPNG(_ image: UIImage) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: pixelSize, height: pixelSize)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.pngData { _ in
            let scale = min(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(
                in: CGRect(
                    x: (size.width - drawn.width) / 2,
                    y: (size.height - drawn.height) / 2,
                    width: drawn.width,
                    height: drawn.height
                )
            )
        }
    }
}
