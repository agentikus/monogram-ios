import Foundation

public struct MonogramJournalEntry: Codable, Equatable {
    public enum Kind: String, Codable {
        case deleted
        case edited
        case media
    }
    
    public let kind: Kind
    public let peerId: Int64
    public let namespace: Int32
    public let id: Int32
    public let date: Int32
    public let peerTitle: String
    public let text: String
    public let oldText: String?
    public let peerUsername: String?
    
    public init(kind: Kind, peerId: Int64, namespace: Int32, id: Int32, date: Int32, peerTitle: String, text: String, oldText: String?, peerUsername: String? = nil) {
        self.kind = kind
        self.peerId = peerId
        self.namespace = namespace
        self.id = id
        self.date = date
        self.peerTitle = peerTitle
        self.text = text
        self.oldText = oldText
        self.peerUsername = peerUsername
    }
}

public final class MonogramJournal {
    public static let shared = MonogramJournal()
    
    private static let maxEntries = 5000
    
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "monogram.journal")
    private let url: URL
    private var items: [MonogramJournalEntry]
    
    private init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.url = directory.appendingPathComponent("monogram_journal.json")
        if let data = try? Data(contentsOf: self.url), let decoded = try? JSONDecoder().decode([MonogramJournalEntry].self, from: data) {
            self.items = decoded
        } else {
            self.items = []
        }
    }
    
    public func entries() -> [MonogramJournalEntry] {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.items
    }
    
    public func add(_ entry: MonogramJournalEntry) {
        self.lock.lock()
        self.items.insert(entry, at: 0)
        if self.items.count > MonogramJournal.maxEntries {
            self.items.removeLast(self.items.count - MonogramJournal.maxEntries)
        }
        let snapshot = self.items
        self.lock.unlock()
        self.persist(snapshot)
        MonogramArchive.shared.log(entry: entry)
    }
    
    public func clear() {
        self.lock.lock()
        self.items = []
        self.lock.unlock()
        self.persist([])
    }
    
    private func persist(_ snapshot: [MonogramJournalEntry]) {
        let url = self.url
        self.ioQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
