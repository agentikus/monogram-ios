import Foundation
import Postbox
import TelegramCore

// Служебный peer-id строки «Claude» в списке чатов. Это не настоящий чат: строка рисуется обычным
// элементом списка, а нажатие перехватывается и открывает экран ИИ.
public let monogramClaudePeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(4_000_000_000_777))

// Задаётся из TelegramUI (ChatListUI не зависит от SettingsUI).
public var monogramClaudeOpenHandler: (() -> Void)?

func monogramClaudeRenderedPeer() -> EngineRenderedPeer {
    let user = TelegramUser(
        id: monogramClaudePeerId,
        accessHash: nil,
        firstName: "Claude",
        lastName: nil,
        username: nil,
        phone: nil,
        photo: [],
        botInfo: nil,
        restrictionInfo: nil,
        flags: [],
        emojiStatus: nil,
        usernames: [],
        storiesHidden: nil,
        nameColor: nil,
        backgroundEmojiId: nil,
        profileColor: nil,
        profileBackgroundEmojiId: nil,
        subscriberCount: nil,
        verificationIconFileId: nil
    )
    let peer = EnginePeer(user)
    return EngineRenderedPeer(peerId: monogramClaudePeerId, peers: [monogramClaudePeerId: peer], associatedMedia: [:])
}

func monogramClaudeMessages() -> [EngineMessage] {
    let settings = MonogramSettings.shared
    let preview = settings.claudeLastPreview
    let text = preview.isEmpty ? "Задайте вопрос ИИ" : preview
    var timestamp = settings.claudeLastTimestamp
    if timestamp == 0 {
        timestamp = Int32(Date().timeIntervalSince1970)
    }
    let message = EngineMessage(
        stableId: 1,
        stableVersion: 1,
        id: EngineMessage.Id(peerId: monogramClaudePeerId, namespace: Namespaces.Message.Cloud, id: 1),
        globallyUniqueId: nil,
        groupingKey: nil,
        groupInfo: nil,
        threadId: nil,
        timestamp: timestamp,
        flags: [.Incoming],
        tags: [],
        globalTags: [],
        localTags: [],
        customTags: [],
        forwardInfo: nil,
        author: nil,
        text: text,
        attributes: [],
        media: [],
        peers: [:],
        associatedMessages: [:],
        associatedMessageIds: [],
        associatedMedia: [:],
        associatedThreadInfo: nil,
        associatedStories: [:]
    )
    return [message]
}
