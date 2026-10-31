import Foundation

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
        if !self.localPremium {
            return false
        }
        self.readPushLock.lock()
        defer {
            self.readPushLock.unlock()
        }
        return self.ownPeerIds.contains(peerId)
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
    
    public static let deletedMarkPresets: [String] = ["🗑 удалено", "🗑", "удалено", "❌ удалено", "👻 удалено"]
    
    public var removeMessageTail: Bool {
        get {
            return (defaults.object(forKey: removeMessageTailKey) as? Bool) ?? false
        }
        set {
            defaults.set(newValue, forKey: removeMessageTailKey)
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
    
    public static let editedMarkPresets: [String] = ["изменено", "✏️ изменено", "✏️", "изм."]
    
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

