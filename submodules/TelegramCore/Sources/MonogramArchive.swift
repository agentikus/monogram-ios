import Foundation
import Postbox

/// Writes deleted/edited/self-destructing content to per-chat folders: first into the app's Documents/Archive
/// (visible in the Files app) and, when the user picked one, into an external folder as well.
public final class MonogramArchive {
    public static let shared = MonogramArchive()

    private let queue = DispatchQueue(label: "monogram.archive")
    private let bookmarkKey = "monogram_archiveBookmark"
    private let folderNameKey = "monogram_archiveFolderName"
    private let maxCopiedFileSize: Int64 = 300 * 1024 * 1024

    private init() {}

    public var externalFolderName: String? {
        return UserDefaults.standard.string(forKey: self.folderNameKey)
    }

    public func setExternalFolder(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return
        }
        UserDefaults.standard.set(data, forKey: self.bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: self.folderNameKey)
        self.queue.async {
            self.syncLocalToExternal()
        }
    }

    public func clearExternalFolder() {
        UserDefaults.standard.removeObject(forKey: self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: self.folderNameKey)
    }

    private func localRoot() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let root = base.appendingPathComponent("Archive", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        return root
    }

    private func resolveExternalRoot() -> (URL, () -> Void)? {
        guard let data = UserDefaults.standard.data(forKey: self.bookmarkKey) else {
            return nil
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        let access = url.startAccessingSecurityScopedResource()
        return (url, {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        })
    }

    private func roots() -> (roots: [URL], finish: () -> Void) {
        var result = [self.localRoot()]
        var finish: () -> Void = {}
        if let (url, stop) = self.resolveExternalRoot() {
            result.append(url)
            finish = stop
        }
        return (result, finish)
    }

    private func sanitized(_ text: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = text.components(separatedBy: forbidden).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(60))
    }

    private func telegramId(_ peerId: Int64) -> Int64 {
        return PeerId(peerId).id._internalGetInt64Value()
    }

    private func chatFolderName(peerId: Int64, title: String) -> String {
        let name = self.sanitized(title)
        return "\(name.isEmpty ? "Chat" : name) [\(self.telegramId(peerId))]"
    }

    private func prepareChatDirectory(root: URL, peerId: Int64, title: String, username: String?) -> URL {
        let directory = root.appendingPathComponent(self.chatFolderName(peerId: peerId, title: title), isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let info = "Имя: \(title)\nUsername: \(username.map { "@\($0)" } ?? "—")\nTelegram ID: \(self.telegramId(peerId))\n"
        try? info.write(to: directory.appendingPathComponent("info.txt"), atomically: true, encoding: .utf8)
        return directory
    }

    private func timestampString(_ date: Int32) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: Double(date)))
    }

    private func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else {
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    func log(entry: MonogramJournalEntry) {
        self.queue.async {
            let line: String
            let when = self.timestampString(entry.date)
            switch entry.kind {
            case .deleted:
                line = "[\(when)] 🗑 УДАЛЕНО (#\(entry.id)): \(entry.text)\n"
            case .edited:
                line = "[\(when)] ✏️ ИЗМЕНЕНО (#\(entry.id))\n    было:  \(entry.oldText ?? "")\n    стало: \(entry.text)\n"
            case .media:
                let fileName = entry.oldText.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
                line = "[\(when)] 📎 \(entry.text) (#\(entry.id)) файл: \(fileName)\n"
            }
            let (roots, finish) = self.roots()
            for root in roots {
                let directory = self.prepareChatDirectory(root: root, peerId: entry.peerId, title: entry.peerTitle, username: entry.peerUsername)
                self.append(line, to: directory.appendingPathComponent("chat.txt"))
            }
            finish()
        }
    }

    /// Copies a file into the chat folder of every root and returns the path inside the app's own archive.
    func storeFile(sourcePath: String, peerId: Int64, title: String, username: String?, fileName: String, completion: @escaping (String?) -> Void) {
        self.queue.async {
            let (roots, finish) = self.roots()
            var localPath: String?
            for (index, root) in roots.enumerated() {
                let directory = self.prepareChatDirectory(root: root, peerId: peerId, title: title, username: username)
                let destination = directory.appendingPathComponent(fileName)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.copyItem(atPath: sourcePath, toPath: destination.path)
                }
                if index == 0, FileManager.default.fileExists(atPath: destination.path) {
                    localPath = destination.path
                }
            }
            finish()
            completion(localPath)
        }
    }

    func archiveMedia(of message: Message, mediaBox: MediaBox, title: String, username: String?, kindText: String, date: Int32) {
        let peerId = message.id.peerId.toInt64()
        let messageId = message.id
        for media in message.media {
            var resource: MediaResource?
            var pathExtension = "jpg"
            if let image = media as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
                resource = representation.resource
            } else if let file = media as? TelegramMediaFile {
                resource = file.resource
                pathExtension = monogramFileExtension(for: file)
            }
            guard let resource, let path = mediaBox.completedResourcePath(resource) else {
                continue
            }
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path), let size = attributes[.size] as? Int64, size > self.maxCopiedFileSize {
                continue
            }
            let fileName = "\(messageId.id)_\(date).\(pathExtension)"
            self.storeFile(sourcePath: path, peerId: peerId, title: title, username: username, fileName: fileName, completion: { localPath in
                if let localPath {
                    MonogramJournal.shared.add(MonogramJournalEntry(kind: .media, peerId: peerId, namespace: messageId.namespace, id: messageId.id, date: date, peerTitle: title, text: kindText, oldText: localPath, peerUsername: username))
                }
            })
        }
    }

    private func syncLocalToExternal() {
        guard let (external, stop) = self.resolveExternalRoot() else {
            return
        }
        defer {
            stop()
        }
        let local = self.localRoot()
        guard let enumerator = FileManager.default.enumerator(at: local, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return
        }
        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: local.path + "/", with: "")
            let destination = external.appendingPathComponent(relative)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)
                continue
            }
            let remoteSize = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? nil
            if remoteSize == nil || remoteSize != Int64(values?.fileSize ?? 0) {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.copyItem(at: url, to: destination)
            }
        }
    }
}
