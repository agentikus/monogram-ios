import Foundation
import Postbox

public class MonogramDeletedMessageAttribute: MessageAttribute {
    public let date: Int32
    
    public init(date: Int32) {
        self.date = date
    }
    
    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

public extension Message {
    var isMonogramDeleted: Bool {
        for attribute in self.attributes {
            if attribute is MonogramDeletedMessageAttribute {
                return true
            }
        }
        return false
    }
}

func markMessagesAsDeletedLocally(transaction: Transaction, ids: [MessageId]) {
    let date = Int32(Date().timeIntervalSince1970)
    for id in ids {
        transaction.updateMessage(id, update: { currentMessage in
            for attribute in currentMessage.attributes {
                if attribute is MonogramDeletedMessageAttribute {
                    return .skip
                }
            }
            var journalText = currentMessage.text
            if journalText.isEmpty && !currentMessage.media.isEmpty {
                journalText = "[медиа]"
            }
            let peerTitle = transaction.getPeer(currentMessage.id.peerId)?.debugDisplayTitle ?? ""
            MonogramJournal.shared.add(MonogramJournalEntry(kind: .deleted, peerId: currentMessage.id.peerId.toInt64(), namespace: currentMessage.id.namespace, id: currentMessage.id.id, date: date, peerTitle: peerTitle, text: journalText, oldText: nil))
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
            }
            var attributes = currentMessage.attributes
            attributes.append(MonogramDeletedMessageAttribute(date: date))
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
    }
}
