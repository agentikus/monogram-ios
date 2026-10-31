import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class MonogramFiltersControllerArguments {
    let add: () -> Void
    let remove: (String) -> Void

    init(add: @escaping () -> Void, remove: @escaping (String) -> Void) {
        self.add = add
        self.remove = remove
    }
}

private enum MonogramFiltersEntry: ItemListNodeEntry {
    case info(String)
    case add(String)
    case filter(Int32, String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        return self.sortIndex
    }

    var sortIndex: Int32 {
        switch self {
        case .info:
            return 0
        case .add:
            return 1
        case let .filter(index, _):
            return 2 + index
        }
    }

    static func ==(lhs: MonogramFiltersEntry, rhs: MonogramFiltersEntry) -> Bool {
        switch lhs {
        case let .info(lhsText):
            if case let .info(rhsText) = rhs, lhsText == rhsText {
                return true
            }
            return false
        case let .add(lhsText):
            if case let .add(rhsText) = rhs, lhsText == rhsText {
                return true
            }
            return false
        case let .filter(lhsIndex, lhsText):
            if case let .filter(rhsIndex, rhsText) = rhs, lhsIndex == rhsIndex, lhsText == rhsText {
                return true
            }
            return false
        }
    }

    static func <(lhs: MonogramFiltersEntry, rhs: MonogramFiltersEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MonogramFiltersControllerArguments
        switch self {
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .add(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case let .filter(_, text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: "Удалить", sectionId: self.section, style: .blocks, action: {
                arguments.remove(text)
            })
        }
    }
}

private func monogramFiltersEntries() -> [MonogramFiltersEntry] {
    var entries: [MonogramFiltersEntry] = []
    entries.append(.info("Входящие сообщения, содержащие фильтр, скрываются в чатах. Регулярные выражения: /шаблон/. Нажмите на фильтр, чтобы удалить."))
    entries.append(.add("Добавить фильтр"))
    var index: Int32 = 0
    for filter in MonogramFilters.shared.filters {
        entries.append(.filter(index, filter))
        index += 1
    }
    return entries
}

public func monogramFiltersController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshCounter = 0

    let arguments = MonogramFiltersControllerArguments(add: {
        let alert = UIAlertController(title: "Новый фильтр", message: "Текст или /регулярное выражение/", preferredStyle: .alert)
        alert.addTextField()
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Добавить", style: .default, handler: { _ in
            let text = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                var filters = MonogramFilters.shared.filters
                if !filters.contains(text) {
                    filters.append(text)
                    MonogramFilters.shared.filters = filters
                }
                refreshCounter += 1
                refresh.set(refreshCounter)
            }
        }))
        context.sharedContext.mainWindow?.presentNative(alert)
    }, remove: { text in
        MonogramFilters.shared.filters = MonogramFilters.shared.filters.filter { $0 != text }
        refreshCounter += 1
        refresh.set(refreshCounter)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        refresh.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Фильтры"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: monogramFiltersEntries(), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
