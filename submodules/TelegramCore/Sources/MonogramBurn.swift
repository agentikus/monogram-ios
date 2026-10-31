import Foundation
import Postbox
import SwiftSignalKit

public func monogramBurnMessage(account: Account, messageId: MessageId) -> Signal<Void, NoError> {
    let postbox = account.postbox
    return _internal_markMessageContentAsConsumedInteractively(postbox: postbox, messageId: messageId)
    |> then(postbox.transaction { transaction -> Void in
        transaction.updateMessage(messageId, update: { currentMessage in
            for attribute in currentMessage.attributes {
                if attribute is MonogramBurnedMessageAttribute {
                    return .skip
                }
            }
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
            }
            var updatedAttributes = currentMessage.attributes
            updatedAttributes.removeAll(where: { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute })
            updatedAttributes.append(MonogramBurnedMessageAttribute(date: Int32(Date().timeIntervalSince1970)))
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: currentMessage.media))
        })
    })
}

public func monogramShouldPeekWithoutConsuming(_ message: EngineRawMessage) -> Bool {
    return MonogramSettings.shared.peekSelfDestructing && message.flags.contains(.Incoming) && message.containsSecretMedia
}
