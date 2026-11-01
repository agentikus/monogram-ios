import Foundation
import Postbox
import SwiftSignalKit

/// Куда писать строки журнала сжигания; подключает приложение (журнал диагностики живёт в UIKit-модуле).
public var monogramLogSink: ((String, String) -> Void)?

func monogramDescribeConsumeState(_ message: Message) -> String {
    var parts: [String] = []
    parts.append(message.flags.contains(.Incoming) ? "входящее" : "исходящее")
    parts.append("чат \(message.id.peerId.namespace)")
    for attribute in message.attributes {
        if let attribute = attribute as? ConsumableContentMessageAttribute {
            parts.append("consumable(просмотрено: \(attribute.consumed))")
        } else if let attribute = attribute as? AutoremoveTimeoutMessageAttribute {
            parts.append("autoremove(таймер \(attribute.timeout), старт \(attribute.countdownBeginTime ?? 0))")
        } else if let attribute = attribute as? AutoclearTimeoutMessageAttribute {
            parts.append("autoclear(таймер \(attribute.timeout), старт \(attribute.countdownBeginTime ?? 0))")
        } else if attribute is MonogramBurnedMessageAttribute {
            parts.append("сожжено")
        }
    }
    for media in message.media {
        if let file = media as? TelegramMediaFile {
            parts.append(file.isInstantVideo ? "кружок" : (file.isVideo ? "видео" : (file.isVoice ? "голосовое" : "файл")))
        } else if media is TelegramMediaImage {
            parts.append("фото")
        } else if media is TelegramMediaExpiredContent {
            parts.append("истёкшее")
        }
    }
    parts.append("флаги: \(message.flags.rawValue)")
    return parts.joined(separator: ", ")
}

public func monogramBurnMessage(account: Account, messageId: MessageId) -> Signal<Void, NoError> {
    let postbox = account.postbox
    let logBefore = postbox.transaction { transaction -> Void in
        if let message = transaction.getMessage(messageId) {
            monogramLogSink?("burn", "перед сжиганием \(messageId.id): " + monogramDescribeConsumeState(message))
        } else {
            monogramLogSink?("burn", "перед сжиганием \(messageId.id): сообщения нет в базе")
        }
    }
    return logBefore
    |> then(_internal_markMessageContentAsConsumedInteractively(postbox: postbox, messageId: messageId))
    |> then(postbox.transaction { transaction -> Void in
        if let message = transaction.getMessage(messageId) {
            monogramLogSink?("burn", "после отметки просмотра \(messageId.id): " + monogramDescribeConsumeState(message))
        }
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
