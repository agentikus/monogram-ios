import Foundation
import Postbox
import SwiftSignalKit

private func monogramSavedMediaDirectory() -> URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let directory = base.appendingPathComponent("MonogramSaved", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    return directory
}

func monogramFileExtension(for file: TelegramMediaFile) -> String {
    if let fileName = file.fileName, let dot = fileName.lastIndex(of: "."), fileName.index(after: dot) < fileName.endIndex {
        return String(fileName[fileName.index(after: dot)...])
    }
    switch file.mimeType {
    case "video/mp4":
        return "mp4"
    case "audio/ogg":
        return "ogg"
    case "audio/mpeg":
        return "mp3"
    case "image/png":
        return "png"
    case "image/webp":
        return "webp"
    case "image/gif":
        return "gif"
    case "image/jpeg":
        return "jpg"
    default:
        return "dat"
    }
}

public func monogramSaveSelfDestructingMedia(postbox: Postbox, message: Message, peerTitle: String, completion: @escaping () -> Void = {}) {
    guard MonogramSettings.shared.saveSelfDestructingMedia else {
        completion()
        return
    }
    var hasTimer = false
    for attribute in message.attributes {
        if attribute is AutoremoveTimeoutMessageAttribute || attribute is AutoclearTimeoutMessageAttribute {
            hasTimer = true
            break
        }
    }
    if !hasTimer {
        completion()
        return
    }
    
    let peerId = message.id.peerId
    let messageId = message.id
    let date = Int32(Date().timeIntervalSince1970)
    
    var pending = 0
    var finished = false
    let finish: () -> Void = {
        if !finished {
            finished = true
            completion()
        }
    }
    let lock = NSLock()
    var items: [(MediaResource, String, String)] = []
    for media in message.media {
        var resource: MediaResource?
        var pathExtension = "jpg"
        var kindText = "[одноразовое фото]"
        if let image = media as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
            resource = representation.resource
        } else if let file = media as? TelegramMediaFile {
            resource = file.resource
            pathExtension = monogramFileExtension(for: file)
            kindText = file.isVideo ? "[одноразовое видео]" : "[одноразовый файл]"
        }
        if let resource {
            items.append((resource, pathExtension, kindText))
        }
    }
    if items.isEmpty {
        finish()
        return
    }
    pending = items.count
    for (itemIndex, item) in items.enumerated() {
        let (resource, pathExtension, kindText) = item
        let fileName = "\(messageId.id)_\(date)_\(itemIndex).\(pathExtension)"
        let peerUsername = message.peers[peerId]?.addressName
        let _ = (postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)).start(next: { data in
            MonogramArchive.shared.storeFile(sourcePath: data.path, peerId: peerId.toInt64(), title: peerTitle, username: peerUsername, fileName: fileName, completion: { localPath in
                if let localPath {
                    MonogramJournal.shared.add(MonogramJournalEntry(kind: .media, peerId: peerId.toInt64(), namespace: messageId.namespace, id: messageId.id, date: date, peerTitle: peerTitle, text: kindText, oldText: localPath, peerUsername: peerUsername))
                }
                lock.lock()
                pending -= 1
                let done = pending <= 0
                lock.unlock()
                if done {
                    finish()
                }
            })
        })
    }
}
