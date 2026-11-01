import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class MonogramStarsControllerArguments {
    let editBalance: () -> Void
    let addOperation: () -> Void
    let editOperation: (String) -> Void
    let addSubscription: () -> Void
    let editSubscription: (String) -> Void

    init(editBalance: @escaping () -> Void, addOperation: @escaping () -> Void, editOperation: @escaping (String) -> Void, addSubscription: @escaping () -> Void, editSubscription: @escaping (String) -> Void) {
        self.editBalance = editBalance
        self.addOperation = addOperation
        self.editOperation = editOperation
        self.addSubscription = addSubscription
        self.editSubscription = editSubscription
    }
}

private enum MonogramStarsEntry: ItemListNodeEntry {
    case header(Int32, String)
    case footer(Int32, String)
    case balance(Int32, String, String)
    case action(Int32, String, Int32)
    case operation(Int32, String, String, String)
    case subscription(Int32, String, String, String)

    var section: ItemListSectionId {
        return self.sortIndex / 1000
    }

    var stableId: Int32 {
        return self.sortIndex
    }

    var sortIndex: Int32 {
        switch self {
        case let .header(index, _), let .footer(index, _), let .balance(index, _, _), let .action(index, _, _), let .operation(index, _, _, _), let .subscription(index, _, _, _):
            return index
        }
    }

    static func ==(lhs: MonogramStarsEntry, rhs: MonogramStarsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a, b), .header(c, d)):
            return a == c && b == d
        case let (.footer(a, b), .footer(c, d)):
            return a == c && b == d
        case let (.balance(a, b, c), .balance(d, e, f)):
            return a == d && b == e && c == f
        case let (.action(a, b, c), .action(d, e, f)):
            return a == d && b == e && c == f
        case let (.operation(a, b, c, d), .operation(e, f, g, h)):
            return a == e && b == f && c == g && d == h
        case let (.subscription(a, b, c, d), .subscription(e, f, g, h)):
            return a == e && b == f && c == g && d == h
        default:
            return false
        }
    }

    static func <(lhs: MonogramStarsEntry, rhs: MonogramStarsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MonogramStarsControllerArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .balance(_, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.editBalance()
            })
        case let .action(_, title, kind):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if kind == 0 {
                    arguments.addOperation()
                } else {
                    arguments.addSubscription()
                }
            })
        case let .operation(_, id, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.editOperation(id)
            })
        case let .subscription(_, id, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.editSubscription(id)
            })
        }
    }
}

private let monogramStarsDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "dd.MM.yyyy HH:mm"
    return formatter
}()

private func monogramStarsDateText(_ date: Int32) -> String {
    return monogramStarsDateFormatter.string(from: Date(timeIntervalSince1970: Double(date)))
}

private func monogramStarsParseDate(_ text: String, fallback: Int32) -> Int32 {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return fallback
    }
    if let date = monogramStarsDateFormatter.date(from: trimmed) {
        return Int32(date.timeIntervalSince1970)
    }
    let shortFormatter = DateFormatter()
    shortFormatter.locale = Locale(identifier: "ru_RU")
    shortFormatter.dateFormat = "dd.MM.yyyy"
    if let date = shortFormatter.date(from: trimmed) {
        return Int32(date.timeIntervalSince1970)
    }
    return fallback
}

private func monogramStarsSignedText(_ amount: Int64) -> String {
    return (amount > 0 ? "+" : "") + "\(amount) ⭐️"
}

private func monogramStarsEntries(accountId: Int64) -> [MonogramStarsEntry] {
    let store = MonogramLocalStars.shared
    var entries: [MonogramStarsEntry] = []

    entries.append(.header(0, "БАЛАНС"))
    if let balance = store.balance(accountId: accountId) {
        entries.append(.balance(1, "Показываемый баланс", "\(balance) ⭐️"))
    } else {
        entries.append(.balance(1, "Показываемый баланс", "настоящий"))
    }
    entries.append(.footer(2, "Число показывается на экране «Звёзды Telegram» и в окнах оплаты для этого аккаунта. Настоящий баланс на сервере не меняется: оплата проходит с него. Оставьте поле пустым, чтобы вернуть настоящий баланс."))

    entries.append(.header(1000, "СВОИ ОПЕРАЦИИ"))
    entries.append(.action(1001, "Добавить операцию", 0))
    var index: Int32 = 1002
    for operation in store.operations(accountId: accountId).sorted(by: { $0.date > $1.date }) {
        entries.append(.operation(index, operation.id, operation.title + " · " + operation.subtitle, monogramStarsSignedText(operation.amount)))
        index += 1
    }
    entries.append(.footer(1999, "Операции видны только на этом телефоне и показываются в списке вместе с настоящими. Нажмите на операцию, чтобы изменить или удалить."))

    entries.append(.header(2000, "СВОИ ПОДПИСКИ"))
    entries.append(.action(2001, "Добавить подписку", 1))
    index = 2002
    for item in store.subscriptions(accountId: accountId).sorted(by: { $0.untilDate > $1.untilDate }) {
        let expired = item.untilDate <= Int32(Date().timeIntervalSince1970)
        let state = expired ? "истекла" : (item.isCancelled ? "отменена" : "активна")
        entries.append(.subscription(index, item.id, item.name, state + " · " + monogramStarsDateText(item.untilDate)))
        index += 1
    }
    entries.append(.footer(2999, "Подписка показывается как активная, пока дата окончания в будущем, и как истёкшая после неё."))
    return entries
}

public func monogramStarsController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshCounter = 0
    let accountId = context.account.peerId.toInt64()
    let store = MonogramLocalStars.shared

    let reload: () -> Void = {
        refreshCounter += 1
        refresh.set(refreshCounter)
        context.starsContext?.load(force: true)
    }

    let present: (UIAlertController) -> Void = { alert in
        context.sharedContext.mainWindow?.presentNative(alert)
    }

    let askOperation: (MonogramLocalStarsOperation?) -> Void = { existing in
        let alert = UIAlertController(title: existing == nil ? "Новая операция" : "Операция", message: "Название, подпись, сумма (минус — списание) и дата дд.мм.гггг чч:мм (пусто — сейчас)", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Название, например: Покупка подарка"
            field.text = existing?.title
        }
        alert.addTextField { field in
            field.placeholder = "Подпись, например: имя пользователя"
            field.text = existing?.subtitle
        }
        alert.addTextField { field in
            field.placeholder = "Сумма, например -50"
            field.keyboardType = .numbersAndPunctuation
            field.text = existing.flatMap { "\($0.amount)" }
        }
        alert.addTextField { field in
            field.placeholder = "Дата"
            field.text = existing.flatMap { monogramStarsDateText($0.date) }
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let existing {
            alert.addAction(UIAlertAction(title: "Удалить", style: .destructive, handler: { _ in
                store.setOperations(accountId: accountId, store.operations(accountId: accountId).filter { $0.id != existing.id })
                reload()
            }))
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
            let fields = alert.textFields ?? []
            let title = (fields[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = (fields[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let amountText = (fields[2].text ?? "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "−", with: "-")
            guard !title.isEmpty, let amount = Int64(amountText), amount != 0 else {
                return
            }
            let date = monogramStarsParseDate(fields[3].text ?? "", fallback: existing?.date ?? Int32(Date().timeIntervalSince1970))
            var operations = store.operations(accountId: accountId)
            let updated = MonogramLocalStarsOperation(id: existing?.id ?? UUID().uuidString, title: title, subtitle: subtitle.isEmpty ? title : subtitle, amount: amount, date: date)
            if let index = operations.firstIndex(where: { $0.id == updated.id }) {
                operations[index] = updated
            } else {
                operations.append(updated)
            }
            store.setOperations(accountId: accountId, operations)
            reload()
        }))
        present(alert)
    }

    let askSubscription: (MonogramLocalStarsSubscription?) -> Void = { existing in
        let alert = UIAlertController(title: existing == nil ? "Новая подписка" : "Подписка", message: "Название, цена в месяц, дата окончания дд.мм.гггг чч:мм и состояние: 1 — отменена, 0 — продлевается. Дата в прошлом — подписка истекла.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Название"
            field.text = existing?.name
        }
        alert.addTextField { field in
            field.placeholder = "Цена в месяц"
            field.keyboardType = .numberPad
            field.text = existing.flatMap { "\($0.price)" }
        }
        alert.addTextField { field in
            field.placeholder = "Дата окончания"
            field.text = existing.flatMap { monogramStarsDateText($0.untilDate) }
        }
        alert.addTextField { field in
            field.placeholder = "Отменена: 1 или 0"
            field.keyboardType = .numberPad
            field.text = (existing?.isCancelled ?? false) ? "1" : "0"
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let existing {
            alert.addAction(UIAlertAction(title: "Удалить", style: .destructive, handler: { _ in
                store.setSubscriptions(accountId: accountId, store.subscriptions(accountId: accountId).filter { $0.id != existing.id })
                reload()
            }))
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
            let fields = alert.textFields ?? []
            let name = (fields[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let price = Int64((fields[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)), price > 0 else {
                return
            }
            let untilDate = monogramStarsParseDate(fields[2].text ?? "", fallback: existing?.untilDate ?? Int32(Date().timeIntervalSince1970) + 30 * 24 * 60 * 60)
            let cancelled = (fields[3].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "1"
            var items = store.subscriptions(accountId: accountId)
            let updated = MonogramLocalStarsSubscription(id: existing?.id ?? UUID().uuidString, name: name, price: price, untilDate: untilDate, isCancelled: cancelled)
            if let index = items.firstIndex(where: { $0.id == updated.id }) {
                items[index] = updated
            } else {
                items.append(updated)
            }
            store.setSubscriptions(accountId: accountId, items)
            reload()
        }))
        present(alert)
    }

    let arguments = MonogramStarsControllerArguments(editBalance: {
        let alert = UIAlertController(title: "Баланс звёзд", message: "Сколько звёзд показывать. Пусто — настоящий баланс.", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "Например 1500"
            field.text = store.balance(accountId: accountId).flatMap { "\($0)" }
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
            let text = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                store.setBalance(accountId: accountId, nil)
            } else if let value = Int64(text), value >= 0 {
                store.setBalance(accountId: accountId, value)
            } else {
                return
            }
            reload()
        }))
        present(alert)
    }, addOperation: {
        askOperation(nil)
    }, editOperation: { id in
        askOperation(store.operations(accountId: accountId).first(where: { $0.id == id }))
    }, addSubscription: {
        askSubscription(nil)
    }, editSubscription: { id in
        askSubscription(store.subscriptions(accountId: accountId).first(where: { $0.id == id }))
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        refresh.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Звёзды (локально)"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: monogramStarsEntries(accountId: accountId), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
