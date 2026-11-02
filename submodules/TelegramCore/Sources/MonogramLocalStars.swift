import Foundation
import Postbox

public struct MonogramLocalStarsOperation: Codable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var amount: Int64
    public var date: Int32
    public var username: String?
    public var peerId: Int64?
    /// nil — обычная запись; "appStore" и "premiumBot" — пополнение с соответствующим источником.
    public var kind: String?
    /// JSON настоящего подарка из каталога (`StarGift`): строка рисуется как подарок со стикером.
    public var giftData: Data?
    /// ID сделки, который показывается в окне операции; без него виден служебный ID записи.
    public var transactionId: String?

    public init(id: String, title: String, subtitle: String, amount: Int64, date: Int32, username: String? = nil, peerId: Int64? = nil, kind: String? = nil, giftData: Data? = nil, transactionId: String? = nil) {
        self.kind = kind
        self.giftData = giftData
        self.transactionId = transactionId
        self.username = username
        self.peerId = peerId
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.amount = amount
        self.date = date
    }
}

public struct MonogramLocalStarsSubscription: Codable, Equatable {
    public var id: String
    public var name: String
    public var price: Int64
    public var untilDate: Int32
    public var isCancelled: Bool
    public var username: String?
    public var peerId: Int64?

    public init(id: String, name: String, price: Int64, untilDate: Int32, isCancelled: Bool, username: String? = nil, peerId: Int64? = nil) {
        self.username = username
        self.peerId = peerId
        self.id = id
        self.name = name
        self.price = price
        self.untilDate = untilDate
        self.isCancelled = isCancelled
    }
}

/// Локальные звёзды: подмена баланса, свои операции и подписки. Хранится отдельно для каждого аккаунта
/// и только на устройстве; серверный баланс и реальные покупки не затрагивает.
public final class MonogramLocalStars {
    public static let shared = MonogramLocalStars()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    private init() {}

    private func key(_ accountId: Int64, _ name: String) -> String {
        return "monogram_localStars_\(name)_\(accountId)"
    }

    public func balance(accountId: Int64) -> Int64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.defaults.object(forKey: self.key(accountId, "balance")) as? Int64
    }

    public func setBalance(accountId: Int64, _ value: Int64?) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let value {
            self.defaults.set(value, forKey: self.key(accountId, "balance"))
        } else {
            self.defaults.removeObject(forKey: self.key(accountId, "balance"))
        }
    }

    /// Если включено, переключатель «Фейк-подарок» в экране отправки подарка стоит включённым сразу.
    public var fakeGiftByDefault: Bool {
        get {
            return self.defaults.bool(forKey: "monogram_localStars_fakeGiftDefault")
        }
        set {
            self.defaults.set(newValue, forKey: "monogram_localStars_fakeGiftDefault")
        }
    }

    /// Настоящие операции и подписки, скрытые пользователем: прячутся из списков на этом устройстве, на сервере остаются.
    public func hiddenIds(accountId: Int64) -> Set<String> {
        self.lock.lock()
        defer { self.lock.unlock() }
        return Set(self.defaults.stringArray(forKey: self.key(accountId, "hidden")) ?? [])
    }

    public func setHiddenIds(accountId: Int64, _ value: Set<String>) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if value.isEmpty {
            self.defaults.removeObject(forKey: self.key(accountId, "hidden"))
        } else {
            self.defaults.set(Array(value), forKey: self.key(accountId, "hidden"))
        }
    }

    public func operations(accountId: Int64) -> [MonogramLocalStarsOperation] {
        return self.load(self.key(accountId, "operations"))
    }

    public func setOperations(accountId: Int64, _ value: [MonogramLocalStarsOperation]) {
        self.store(self.key(accountId, "operations"), value)
    }

    public func subscriptions(accountId: Int64) -> [MonogramLocalStarsSubscription] {
        return self.load(self.key(accountId, "subscriptions"))
    }

    public func setSubscriptions(accountId: Int64, _ value: [MonogramLocalStarsSubscription]) {
        self.store(self.key(accountId, "subscriptions"), value)
    }

    private func load<T: Decodable>(_ key: String) -> [T] {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let data = self.defaults.data(forKey: key), let value = try? JSONDecoder().decode([T].self, from: data) else {
            return []
        }
        return value
    }

    private func store<T: Encodable>(_ key: String, _ value: [T]) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let data = try? JSONEncoder().encode(value) {
            self.defaults.set(data, forKey: key)
        }
    }

    /// Настоящий пользователь, найденный по юзернейму, даёт строке только аватарку: имя в строке всегда то,
    /// которое ввёл сам пользователь, а ник и остальные признаки настоящего аккаунта не переносятся.
    func peer(_ real: Peer?, named name: String, seed: String) -> Peer {
        guard let real = real else {
            return self.fakePeer(seed: seed, name: name)
        }
        guard let user = real as? TelegramUser, !name.isEmpty else {
            return real
        }
        return TelegramUser(id: user.id, accessHash: user.accessHash, firstName: name, lastName: nil, username: nil, phone: nil, photo: user.photo, botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: user.nameColor, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    /// ID сделки в том виде, как его показывает Telegram: «stx» и url-безопасный base64 из 32 случайных байт.
    public static func makeTransactionId() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var result = "stx"
        for _ in 0 ..< 43 {
            result.append(alphabet[Int.random(in: 0 ..< alphabet.count)])
        }
        return result
    }

    /// Выдуманный пользователь для названия в строке: у локальной записи нет настоящего собеседника.
    func fakePeer(seed: String, name: String) -> TelegramUser {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        let id = Int64(7_000_000_000_000 + Int64(hash % 900_000_000_000))
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id)), accessHash: nil, firstName: name, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }
}

extension MonogramLocalStars {
    func applying(to status: InternalStarsStatus, transaction: Transaction, accountId: Int64, ton: Bool, mode: StarsTransactionsContext.Mode, firstPage: Bool) -> InternalStarsStatus {
        if ton {
            return status
        }
        var balance = status.balance
        if let override = self.balance(accountId: accountId) {
            balance = StarsAmount(value: override, nanos: 0)
        }
        let hidden = self.hiddenIds(accountId: accountId)
        var transactions = hidden.isEmpty ? status.transactions : status.transactions.filter { !hidden.contains($0.id) }
        if firstPage {
            for operation in self.operations(accountId: accountId) {
                switch mode {
                case .incoming:
                    if operation.amount <= 0 {
                        continue
                    }
                case .outgoing:
                    if operation.amount >= 0 {
                        continue
                    }
                case .all:
                    break
                }
                let transactionPeer: StarsContext.State.Transaction.Peer
                switch operation.kind {
                case "appStore":
                    transactionPeer = .appStore
                case "premiumBot":
                    transactionPeer = .premiumBot
                default:
                    let peer: Peer = self.peer(operation.peerId.flatMap { transaction.getPeer(PeerId($0)) }, named: operation.subtitle, seed: operation.id)
                    transactionPeer = .peer(EnginePeer(peer))
                }
                let starGift: StarGift? = operation.giftData.flatMap { try? JSONDecoder().decode(StarGift.self, from: $0) }
                let transaction = StarsContext.State.Transaction(flags: operation.kind == "uniqueBuy" ? [.isStarGiftResale] : [], id: operation.transactionId ?? ("monogram-local-" + operation.id), count: CurrencyAmount(amount: StarsAmount(value: operation.amount, nanos: 0), currency: .stars), date: operation.date, peer: transactionPeer, title: operation.title, description: nil, photo: nil, transactionDate: nil, transactionUrl: nil, paidMessageId: nil, giveawayMessageId: nil, media: [], subscriptionPeriod: nil, starGift: starGift, floodskipNumber: nil, starrefCommissionPermille: nil, starrefPeerId: nil, starrefAmount: nil, paidMessageCount: nil, premiumGiftMonths: nil, adsProceedsFromDate: nil, adsProceedsToDate: nil)
                transactions.append(transaction)
            }
            transactions = transactions.enumerated().sorted(by: { lhs, rhs in
                if lhs.element.date != rhs.element.date {
                    return lhs.element.date > rhs.element.date
                }
                return lhs.offset < rhs.offset
            }).map { $0.element }
        }
        return InternalStarsStatus(balance: balance, subscriptionsMissingBalance: status.subscriptionsMissingBalance, subscriptions: status.subscriptions, nextSubscriptionsOffset: status.nextSubscriptionsOffset, transactions: transactions, nextTransactionsOffset: status.nextTransactionsOffset)
    }

    func applying(to status: InternalStarsStatus, transaction: Transaction, accountId: Int64, missingBalance: Bool, firstPage: Bool) -> InternalStarsStatus {
        var balance = status.balance
        if let override = self.balance(accountId: accountId) {
            balance = StarsAmount(value: override, nanos: 0)
        }
        let hidden = self.hiddenIds(accountId: accountId)
        var subscriptions = hidden.isEmpty ? status.subscriptions : status.subscriptions.filter { !hidden.contains($0.id) }
        if firstPage && !missingBalance {
            for item in self.subscriptions(accountId: accountId) {
                let peer: Peer = self.peer(item.peerId.flatMap { transaction.getPeer(PeerId($0)) }, named: item.name, seed: item.id)
                var flags: StarsContext.State.Subscription.Flags = []
                if item.isCancelled {
                    flags.insert(.isCancelled)
                }
                subscriptions.append(StarsContext.State.Subscription(flags: flags, id: "monogram-local-" + item.id, peer: EnginePeer(peer), untilDate: item.untilDate, pricing: StarsSubscriptionPricing(period: 2592000, amount: StarsAmount(value: item.price, nanos: 0)), inviteHash: nil, title: nil, photo: nil, invoiceSlug: nil))
            }
            subscriptions = subscriptions.enumerated().sorted(by: { lhs, rhs in
                let lhsActive = lhs.element.untilDate > Int32(Date().timeIntervalSince1970)
                let rhsActive = rhs.element.untilDate > Int32(Date().timeIntervalSince1970)
                if lhsActive != rhsActive {
                    return lhsActive
                }
                return lhs.offset < rhs.offset
            }).map { $0.element }
        }
        return InternalStarsStatus(balance: balance, subscriptionsMissingBalance: status.subscriptionsMissingBalance, subscriptions: subscriptions, nextSubscriptionsOffset: status.nextSubscriptionsOffset, transactions: status.transactions, nextTransactionsOffset: status.nextTransactionsOffset)
    }
}
