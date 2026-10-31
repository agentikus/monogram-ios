import Foundation
import Postbox
import SwiftSignalKit

private func monogramSavedMediaDirectory() -> URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let directory = base.appendingPathComponent("MonogramSaved", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    return directory
}

private func monogramFileExtension(for file: TelegramMediaFile) -> String {
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

func monogramSaveSelfDestructingMedia(postbox: Postbox, message: Message, peerTitle: String) {
    guard MonogramSettings.shared.saveSelfDestructingMedia else {
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
        return
    }
    
    let peerId = message.id.peerId
    let messageId = message.id
    let date = Int32(Date().timeIntervalSince1970)
    
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
        guard let resource else {
            continue
        }
        let destination = monogramSavedMediaDirectory().appendingPathComponent("\(peerId.toInt64())_\(messageId.id)_\(date).\(pathExtension)")
        let _ = (postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)).start(next: { data in
            try? FileManager.default.copyItem(atPath: data.path, toPath: destination.path)
            MonogramJournal.shared.add(MonogramJournalEntry(kind: .media, peerId: peerId.toInt64(), namespace: messageId.namespace, id: messageId.id, date: date, peerTitle: peerTitle, text: kindText, oldText: destination.path))
        })
    }
}
