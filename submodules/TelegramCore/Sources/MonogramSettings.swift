import Foundation
import Security
import Postbox

public final class MonogramSettings {
    public static let shared = MonogramSettings()
    
    private let defaults = UserDefaults.standard
    
    private let sendOnlineKey = "monogram_sendOnline"
    private let sendTypingKey = "monogram_sendTyping"
    private let sendReadMessagesKey = "monogram_sendReadMessages"
    private let sendReadStoriesKey = "monogram_sendReadStories"
    private let saveDeletedMessagesKey = "monogram_saveDeletedMessages"
    private let markEditedMessagesKey = "monogram_markEditedMessages"
    private let confirmVoiceAndVideoKey = "monogram_confirmVoiceAndVideo"
    private let disableAdsKey = "monogram_disableAds"
    private let hidePremiumStatusesKey = "monogram_hidePremiumStatuses"
    private let useScheduledMessagesKey = "monogram_useScheduledMessages"
    private let filtersEnabledKey = "monogram_filtersEnabled"
    private let hideNotificationBadgeKey = "monogram_hideNotificationBadge"
    private let hideNotificationCountersKey = "monogram_hideNotificationCounters"
    private let hideAllChatsFolderKey = "monogram_hideAllChatsFolder"
    private let streamerModeKey = "monogram_streamerMode"
    private let showPeerIdKey = "monogram_showPeerId"
    private let translationProviderKey = "monogram_translationProvider"
    private let semiTransparentDeletedKey = "monogram_semiTransparentDeleted"
    private let markReadAfterActionKey = "monogram_markReadAfterAction"
    private let showMessageDetailsKey = "monogram_showMessageDetails"
    private let disableStoriesKey = "monogram_disableStories"
    private let editedMarkKey = "monogram_editedMark"
    private let sendSilentInGhostKey = "monogram_sendSilentInGhost"
    private let showMessageSecondsKey = "monogram_showMessageSeconds"
    private let suggestGhostBeforeStoryKey = "monogram_suggestGhostBeforeStory"
    private let removeMessageTailKey = "monogram_removeMessageTail"
    private let deletedMarkKey = "monogram_deletedMark"
    private let saveSelfDestructingMediaKey = "monogram_saveSelfDestructingMedia"
    private let localPremiumKey = "monogram_localPremium"
    
    private let readPushLock = NSLock()
    private var readPushAllowedPeers = Set<Int64>()
    
    private init() {}
    
    private var ownPeerIds = Set<Int64>()
    
    func registerOwnPeerId(_ peerId: Int64) {
        self.readPushLock.lock()
        self.ownPeerIds.insert(peerId)
        self.readPushLock.unlock()
    }
    
    func isLocalPremiumPeer(_ peerId: Int64) -> Bool {
        self.readPushLock.lock()
        let isOwn = self.ownPeerIds.contains(peerId)
        self.readPushLock.unlock()
        return isOwn && self.localPremium
    }
    
    private let burnedKey = "monogram_burnedMessages"
    private var burnedMessages: Set<String>?
    
    private func burnKey(_ id: MessageId) -> String {
        return "\(id.peerId.toInt64())_\(id.namespace)_\(id.id)"
    }
    
    public func markBurned(_ id: MessageId) {
        self.readPushLock.lock()
        var burned = self.burnedMessages ?? Set(self.defaults.stringArray(forKey: self.burnedKey) ?? [])
        burned.insert(self.burnKey(id))
        self.burnedMessages = burned
        self.defaults.set(Array(burned), forKey: self.burnedKey)
        self.readPushLock.unlock()
    }
    
    func isBurned(_ id: MessageId) -> Bool {
        self.readPushLock.lock()
        defer {
            self.readPushLock.unlock()
        }
        if self.burnedMessages == nil {
            self.burnedMessages = Set(self.defaults.stringArray(forKey: self.burnedKey) ?? [])
        }
        return self.burnedMessages!.contains(self.burnKey(id))
    }
    
    func keepsSelfDestructingMedia(_ id: MessageId) -> Bool {
        return self.saveSelfDestructingMedia && !self.isBurned(id)
    }
    
    func setReadPushAllowed(_ peerId: Int64, _ allowed: Bool) {
        self.readPushLock.lock()
        if allowed {
            self.readPushAllowedPeers.insert(peerId)
        } else {
            self.readPushAllowedPeers.remove(peerId)
        }
        self.readPushLock.unlock()
    }
    
    func isReadPushAllowed(_ peerId: Int64) -> Bool {
        self.readPushLock.lock()
        defer {
            self.readPushLock.unlock()
        }
        return self.readPushAllowedPeers.contains(peerId)
    }
    
    public var sendOnline: Bool {
        get {
            return (defaults.object(forKey: sendOnlineKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: sendOnlineKey)
        }
    }
    
    public var sendTyping: Bool {
        get {
            return (defaults.object(forKey: sendTypingKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: sendTypingKey)
        }
    }
    
    public var sendReadMessages: Bool {
        get {
            return (defaults.object(forKey: sendReadMessagesKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: sendReadMessagesKey)
        }
    }
    
    public var sendReadStories: Bool {
        get {
            return (defaults.object(forKey: sendReadStoriesKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: sendReadStoriesKey)
        }
    }
    
    public var saveDeletedMessages: Bool {
        get {
            return (defaults.object(forKey: saveDeletedMessagesKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: saveDeletedMessagesKey)
        }
    }
    
    public var markEditedMessages: Bool {
        get {
            return (defaults.object(forKey: markEditedMessagesKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: markEditedMessagesKey)
        }
    }
    
    public var confirmVoiceAndVideo: Bool {
        get {
            return (defaults.object(forKey: confirmVoiceAndVideoKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: confirmVoiceAndVideoKey)
        }
    }
    
    public var saveSelfDestructingMedia: Bool {
        get {
            return (defaults.object(forKey: saveSelfDestructingMediaKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: saveSelfDestructingMediaKey)
        }
    }
    
    public static let deletedMarkPresets: [String] = ["🗑 удалено", "🗑", "удалено", "❌ удалено", "👻 удалено", "🧹", "🧹 удалено"]
    
    public var removeMessageTail: Bool {
        get {
            return (defaults.object(forKey: removeMessageTailKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: removeMessageTailKey)
        }
    }
    
    public static let burnedMarkPresets: [String] = ["🔥 уничтожено", "🔥", "уничтожено", "💥 уничтожено", "🧹 уничтожено"]
    
    public var burnedMark: String {
        get {
            return defaults.string(forKey: "monogram_burnedMark") ?? MonogramSettings.burnedMarkPresets[0]
        }
        set {
            defaults.set(newValue, forKey: "monogram_burnedMark")
        }
    }
    
    public var deletedMark: String {
        get {
            return defaults.string(forKey: deletedMarkKey) ?? MonogramSettings.deletedMarkPresets[0]
        }
        set {
            defaults.set(newValue, forKey: deletedMarkKey)
        }
    }
    
    public var suggestGhostBeforeStory: Bool {
        get {
            return (defaults.object(forKey: suggestGhostBeforeStoryKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: suggestGhostBeforeStoryKey)
        }
    }
    
    public static let editedMarkPresets: [String] = ["изменено", "✏️ изменено", "✏️", "изм.", "📝", "📝 изменено"]
    
    public var disableStories: Bool {
        get {
            return (defaults.object(forKey: disableStoriesKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: disableStoriesKey)
        }
    }
    
    public var editedMark: String {
        get {
            return defaults.string(forKey: editedMarkKey) ?? MonogramSettings.editedMarkPresets[0]
        }
        set {
            defaults.set(newValue, forKey: editedMarkKey)
        }
    }
    
    public var sendSilentInGhost: Bool {
        get {
            return (defaults.object(forKey: sendSilentInGhostKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: sendSilentInGhostKey)
        }
    }
    
    public var showMessageSeconds: Bool {
        get {
            return (defaults.object(forKey: showMessageSecondsKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: showMessageSecondsKey)
        }
    }
    
    public var showMessageDetails: Bool {
        get {
            return (defaults.object(forKey: showMessageDetailsKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: showMessageDetailsKey)
        }
    }
    
    public var semiTransparentDeleted: Bool {
        get {
            return (defaults.object(forKey: semiTransparentDeletedKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: semiTransparentDeletedKey)
        }
    }
    
    public var markReadAfterAction: Bool {
        get {
            return (defaults.object(forKey: markReadAfterActionKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: markReadAfterActionKey)
        }
    }
    
    public var peekSelfDestructing: Bool {
        get {
            return (defaults.object(forKey: "monogram_peekSelfDestructing") as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: "monogram_peekSelfDestructing")
        }
    }
    
    public var localTranscription: Bool {
        get {
            return (defaults.object(forKey: "monogram_localTranscription") as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: "monogram_localTranscription")
        }
    }
    
    private func boolValue(_ key: String, _ defaultValue: Bool) -> Bool {
        return (self.defaults.object(forKey: key) as? Bool) ?? defaultValue
    }

    public var confirmStickersAndGifs: Bool {
        get { return self.boolValue("monogram_confirmStickersAndGifs", true) }
        set { self.defaults.set(newValue, forKey: "monogram_confirmStickersAndGifs") }
    }

    public var disableCustomChatBackgrounds: Bool {
        get { return self.boolValue("monogram_disableCustomChatBackgrounds", false) }
        set { self.defaults.set(newValue, forKey: "monogram_disableCustomChatBackgrounds") }
    }

    public var hideGreetingSticker: Bool {
        get { return self.boolValue("monogram_hideGreetingSticker", true) }
        set { self.defaults.set(newValue, forKey: "monogram_hideGreetingSticker") }
    }

    public var filterZalgo: Bool {
        get { return self.boolValue("monogram_filterZalgo", true) }
        set { self.defaults.set(newValue, forKey: "monogram_filterZalgo") }
    }

    private func keychainQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "monogram.claude",
            kSecAttrAccount as String: "apiKey"
        ]
    }

    /// Хранится в Keychain (только на этом устройстве). Старое значение из UserDefaults переносится при первом чтении.
    public var claudeApiKey: String {
        get {
            var query = self.keychainQuery()
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) {
                return value
            }
            if let legacy = self.defaults.string(forKey: "monogram_claudeApiKey"), !legacy.isEmpty {
                self.claudeApiKey = legacy
                self.defaults.removeObject(forKey: "monogram_claudeApiKey")
                return legacy
            }
            return ""
        }
        set {
            SecItemDelete(self.keychainQuery() as CFDictionary)
            if newValue.isEmpty {
                return
            }
            var attributes = self.keychainQuery()
            attributes[kSecValueData as String] = Data(newValue.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    public static let claudeModels: [(id: String, title: String)] = [
        ("claude-haiku-5-5", "Haiku 5.5"),
        ("claude-sonnet-5-5", "Sonnet 5.5"),
        ("claude-opus-5-5", "Opus 5.5")
    ]

    public var claudeModel: String {
        get { return self.defaults.string(forKey: "monogram_claudeModel") ?? "claude-haiku-5-5" }
        set { self.defaults.set(newValue, forKey: "monogram_claudeModel") }
    }

    public static let claudeEfforts: [(id: String, title: String)] = [
        ("low", "Низкое"),
        ("medium", "Среднее"),
        ("high", "Высокое")
    ]

    public var claudeEffort: String {
        get { return self.defaults.string(forKey: "monogram_claudeEffort") ?? "low" }
        set { self.defaults.set(newValue, forKey: "monogram_claudeEffort") }
    }

    public var hideScreenshotNotifications: Bool {
        get {
            return (defaults.object(forKey: "monogram_hideScreenshotNotifications") as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: "monogram_hideScreenshotNotifications")
        }
    }
    
    public var ignoreCopyProtection: Bool {
        get {
            return (defaults.object(forKey: "monogram_ignoreCopyProtection") as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: "monogram_ignoreCopyProtection")
        }
    }
    
    public var hidePremiumStatuses: Bool {
        get {
            return (defaults.object(forKey: hidePremiumStatusesKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: hidePremiumStatusesKey)
        }
    }
    
    public var useScheduledMessages: Bool {
        get {
            return (defaults.object(forKey: useScheduledMessagesKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: useScheduledMessagesKey)
        }
    }
    
    public var filtersEnabled: Bool {
        get {
            return (defaults.object(forKey: filtersEnabledKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: filtersEnabledKey)
        }
    }
    
    public var hideNotificationBadge: Bool {
        get {
            return (defaults.object(forKey: hideNotificationBadgeKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: hideNotificationBadgeKey)
        }
    }
    
    public var hideNotificationCounters: Bool {
        get {
            return (defaults.object(forKey: hideNotificationCountersKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: hideNotificationCountersKey)
        }
    }
    
    public var hideAllChatsFolder: Bool {
        get {
            return (defaults.object(forKey: hideAllChatsFolderKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: hideAllChatsFolderKey)
        }
    }
    
    public var streamerMode: Bool {
        get {
            return (defaults.object(forKey: streamerModeKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: streamerModeKey)
        }
    }
    
    public var showPeerId: Bool {
        get {
            return (defaults.object(forKey: showPeerIdKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: showPeerIdKey)
        }
    }
    
    public static let translationProviders: [(id: String, title: String)] = [("telegram", "Telegram"), ("google", "Google")]
    
    public var translationProvider: String {
        get {
            return defaults.string(forKey: translationProviderKey) ?? "telegram"
        }
        set {
            defaults.set(newValue, forKey: translationProviderKey)
        }
    }
    
    public var disableAds: Bool {
        get {
            return (defaults.object(forKey: disableAdsKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: disableAdsKey)
        }
    }
    
    public var localPremium: Bool {
        get {
            return (defaults.object(forKey: localPremiumKey) as? Bool) ?? true
        }
        set {
            defaults.set(newValue, forKey: localPremiumKey)
        }
    }
    
    public var isGhostModeActive: Bool {
        get {
            return !sendOnline && !sendTyping && !sendReadMessages && !sendReadStories
        }
        set {
            if newValue {
                sendOnline = false
                sendTyping = false
                sendReadMessages = false
                sendReadStories = false
            } else {
                sendOnline = true
                sendTyping = true
                sendReadMessages = true
                sendReadStories = true
            }
        }
    }
}

