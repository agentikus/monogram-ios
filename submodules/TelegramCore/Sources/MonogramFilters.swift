import Foundation
import Postbox

public final class MonogramFilters {
    public static let shared = MonogramFilters()
    
    private let key = "monogram_messageFilters"
    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var regexCache: [String: NSRegularExpression] = [:]
    
    private init() {}
    
    private var cachedFilters: [String]?

    public var filters: [String] {
        get {
            self.lock.lock()
            defer {
                self.lock.unlock()
            }
            if let cachedFilters = self.cachedFilters {
                return cachedFilters
            }
            let value = self.defaults.stringArray(forKey: self.key) ?? []
            self.cachedFilters = value
            return value
        }
        set {
            self.lock.lock()
            self.cachedFilters = newValue
            self.lock.unlock()
            self.defaults.set(newValue, forKey: self.key)
        }
    }
    
    private func regex(for pattern: String) -> NSRegularExpression? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if let cached = self.regexCache[pattern] {
            return cached
        }
        guard let created = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        self.regexCache[pattern] = created
        return created
    }
    
    public func matches(text: String) -> Bool {
        if text.isEmpty || !MonogramSettings.shared.filtersEnabled {
            return false
        }
        let filters = self.filters
        if filters.isEmpty {
            return false
        }
        let lowered = text.lowercased()
        for filter in filters {
            if filter.count > 2 && filter.hasPrefix("/") && filter.hasSuffix("/") {
                let pattern = String(filter.dropFirst().dropLast())
                if let regex = self.regex(for: pattern), regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) != nil {
                    return true
                }
            } else if !filter.isEmpty && lowered.contains(filter.lowercased()) {
                return true
            }
        }
        return false
    }
    
    public func shouldHide(message: Message) -> Bool {
        if !message.flags.contains(.Incoming) {
            return false
        }
        return self.matches(text: message.text)
    }
}
