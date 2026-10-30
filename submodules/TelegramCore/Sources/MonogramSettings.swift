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
    
    private init() {}
    
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

