import Foundation
import Security

/// Настройки ИИ-чата. Отдельный лёгкий модуль без зависимостей: правки здесь не пересобирают ядро (TelegramCore).
public final class MonogramAISettings {
    public static let shared = MonogramAISettings()

    private let defaults = UserDefaults.standard

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

    public var showClaudeChat: Bool {
        get { return (self.defaults.object(forKey: "monogram_showClaudeChat") as? Bool) ?? true }
        set { self.defaults.set(newValue, forKey: "monogram_showClaudeChat") }
    }

    public var claudeLastPreview: String {
        get { return self.defaults.string(forKey: "monogram_claudeLastPreview") ?? "" }
        set { self.defaults.set(newValue, forKey: "monogram_claudeLastPreview") }
    }

    public var claudeLastTimestamp: Int32 {
        get { return Int32(truncatingIfNeeded: self.defaults.integer(forKey: "monogram_claudeLastTimestamp")) }
        set { self.defaults.set(Int(newValue), forKey: "monogram_claudeLastTimestamp") }
    }
}
