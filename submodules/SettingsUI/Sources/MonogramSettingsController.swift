import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class MonogramSettingsControllerArguments {
    let toggle: (MonogramSettingsOption, Bool) -> Void

    init(toggle: @escaping (MonogramSettingsOption, Bool) -> Void) {
        self.toggle = toggle
    }
}

private enum MonogramSettingsOption: Int32 {
    case ghostMode
    case hideOnline
    case hideTyping
    case hideReadMessages
    case hideReadStories
    case saveDeleted
    case markEdited
}

private enum MonogramSettingsEntry: ItemListNodeEntry {
    case header(Int32, String)
    case toggle(Int32, MonogramSettingsOption, String, Bool)
    case footer(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(index, _), let .footer(index, _), let .toggle(index, _, _, _):
            return index < 100 ? 0 : 1
        }
    }

    var stableId: Int32 {
        return self.sortIndex
    }

    var sortIndex: Int32 {
        switch self {
        case let .header(index, _), let .footer(index, _), let .toggle(index, _, _, _):
            return index
        }
    }

    static func ==(lhs: MonogramSettingsEntry, rhs: MonogramSettingsEntry) -> Bool {
        switch lhs {
        case let .header(lhsIndex, lhsText):
            if case let .header(rhsIndex, rhsText) = rhs, lhsIndex == rhsIndex, lhsText == rhsText {
                return true
            }
            return false
        case let .footer(lhsIndex, lhsText):
            if case let .footer(rhsIndex, rhsText) = rhs, lhsIndex == rhsIndex, lhsText == rhsText {
                return true
            }
            return false
        case let .toggle(lhsIndex, lhsOption, lhsTitle, lhsValue):
            if case let .toggle(rhsIndex, rhsOption, rhsTitle, rhsValue) = rhs, lhsIndex == rhsIndex, lhsOption == rhsOption, lhsTitle == rhsTitle, lhsValue == rhsValue {
                return true
            }
            return false
        }
    }

    static func <(lhs: MonogramSettingsEntry, rhs: MonogramSettingsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MonogramSettingsControllerArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .toggle(_, option, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(option, value)
            })
        }
    }
}

private func monogramSettingsEntries() -> [MonogramSettingsEntry] {
    let settings = MonogramSettings.shared
    var entries: [MonogramSettingsEntry] = []

    entries.append(.header(0, "РЕЖИМ ПРИЗРАКА"))
    entries.append(.toggle(1, .ghostMode, "Режим призрака", settings.isGhostModeActive))
    entries.append(.toggle(2, .hideOnline, "Не показывать, что я в сети", !settings.sendOnline))
    entries.append(.toggle(3, .hideTyping, "Не показывать «печатает…»", !settings.sendTyping))
    entries.append(.toggle(4, .hideReadMessages, "Не отмечать сообщения прочитанными", !settings.sendReadMessages))
    entries.append(.toggle(5, .hideReadStories, "Не отмечать истории просмотренными", !settings.sendReadStories))
    entries.append(.footer(6, "Собеседники не увидят, что вы онлайн, печатаете или прочитали сообщение. Ответ на сообщение или действие в чате может отправить отметку «прочитано»."))

    entries.append(.header(100, "СООБЩЕНИЯ"))
    entries.append(.toggle(101, .saveDeleted, "Сохранять удалённые сообщения", settings.saveDeletedMessages))
    entries.append(.toggle(102, .markEdited, "Сохранять исходный текст изменённых", settings.markEditedMessages))
    entries.append(.footer(103, "Удалённые сообщения остаются в чате и помечаются значком корзины. У изменённых сообщений внизу добавляется исходный текст в формате «[Было: …]»."))

    return entries
}

public func monogramSettingsController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshCounter = 0

    let arguments = MonogramSettingsControllerArguments(toggle: { option, value in
        let settings = MonogramSettings.shared
        switch option {
        case .ghostMode:
            settings.isGhostModeActive = value
        case .hideOnline:
            settings.sendOnline = !value
        case .hideTyping:
            settings.sendTyping = !value
        case .hideReadMessages:
            settings.sendReadMessages = !value
        case .hideReadStories:
            settings.sendReadStories = !value
        case .saveDeleted:
            settings.saveDeletedMessages = value
        case .markEdited:
            settings.markEditedMessages = value
        }
        refreshCounter += 1
        refresh.set(refreshCounter)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        refresh.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Monogram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: monogramSettingsEntries(), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
