import Foundation
import Postbox
import SwiftSignalKit

public func monogramBurnMessage(account: Account, messageId: MessageId) -> Signal<Void, NoError> {
    MonogramSettings.shared.markBurned(messageId)
    let postbox = account.postbox
    return _internal_markMessageContentAsConsumedInteractively(postbox: postbox, messageId: messageId)
    |> then(postbox.transaction { transaction -> Void in
        guard let message = transaction.getMessage(messageId) else {
            return
        }
        var isInstantVideo = false
        for media in message.media {
            if let file = media as? TelegramMediaFile, file.isInstantVideo {
                isInstantVideo = true
            }
        }
        if !isInstantVideo {
            _internal_deleteMessages(transaction: transaction, mediaBox: postbox.mediaBox, ids: [messageId])
            return
        }
        transaction.updateMessage(messageId, update: { currentMessage in
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
            }
            var updatedMedia = currentMessage.media
            for i in 0 ..< updatedMedia.count {
                if let file = updatedMedia[i] as? TelegramMediaFile, file.isInstantVideo {
                    updatedMedia[i] = TelegramMediaExpiredContent(data: .videoMessage)
                }
            }
            var updatedAttributes = currentMessage.attributes
            updatedAttributes.removeAll(where: { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute })
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: updatedMedia))
        })
    })
}

public func monogramShouldPeekWithoutConsuming(_ message: EngineRawMessage) -> Bool {
    return MonogramSettings.shared.peekSelfDestructing && message.flags.contains(.Incoming) && message.containsSecretMedia
}
