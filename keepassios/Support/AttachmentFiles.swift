import Foundation

/// Temporary files for attachments being previewed or shared. Attachments
/// live inside the encrypted database; a copy is written only while the
/// user looks at or shares one, and removed afterwards.
enum AttachmentFiles {
    /// Writes `data` to a temporary file with the attachment's name.
    static func temporaryCopy(named name: String, data: Data) -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(safeFileName(name))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    /// Removes a copy made by `temporaryCopy(named:data:)`.
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// `name`, or "name (2).ext", "name (3).ext"… if it's already taken.
    static func uniqueName(_ name: String, existing: some Collection<String>) -> String {
        guard existing.contains(name) else { return name }
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)"
            if !existing.contains(candidate) { return candidate }
            number += 1
        }
    }

    /// Attachment names come from other apps; keep them usable as file names.
    private static func safeFileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? "Attachment" : cleaned
    }
}
