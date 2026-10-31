import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class MonogramDocumentPreviewDelegate: NSObject, UIDocumentInteractionControllerDelegate {
    private weak var presenter: UIViewController?

    init(presenter: UIViewController) {
        self.presenter = presenter
        super.init()
    }

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self.presenter ?? UIViewController()
    }
}

private var monogramDocumentPreviewHolder: (UIDocumentInteractionController, MonogramDocumentPreviewDelegate)?

private final class MonogramJournalControllerArguments {
    let open: (MonogramJournalEntry) -> Void
    let clear: () -> Void
    
    init(open: @escaping (MonogramJournalEntry) -> Void, clear: @escaping () -> Void) {
        self.open = open
        self.clear = clear
    }
}

private enum MonogramJournalEntryItem: ItemListNodeEntry {
    case info(String)
    case item(Int32, MonogramJournalEntry, String, String)
    case clear(Int32, String)
    
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
        case let .item(index, _, _, _):
            return 1 + index
        case let .clear(index, _):
            return index
        }
    }
    
    static func ==(lhs: MonogramJournalEntryItem, rhs: MonogramJournalEntryItem) -> Bool {
        switch lhs {
        case let .info(lhsText):
            if case let .info(rhsText) = rhs, lhsText == rhsText {
                return true
            }
            return false
        case let .item(lhsIndex, lhsEntry, lhsTitle, lhsLabel):
            if case let .item(rhsIndex, rhsEntry, rhsTitle, rhsLabel) = rhs, lhsIndex == rhsIndex, lhsEntry == rhsEntry, lhsTitle == rhsTitle, lhsLabel == rhsLabel {
                return true
            }
            return false
        case let .clear(lhsIndex, lhsText):
            if case let .clear(rhsIndex, rhsText) = rhs, lhsIndex == rhsIndex, lhsText == rhsText {
                return true
            }
            return false
        }
    }
    
    static func <(lhs: MonogramJournalEntryItem, rhs: MonogramJournalEntryItem) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MonogramJournalControllerArguments
        switch self {
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .item(_, entry, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: {
                arguments.open(entry)
            })
        case let .clear(_, text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clear()
            })
        }
    }
}

private func shortened(_ text: String, limit: Int) -> String {
    let flat = text.replacingOccurrences(of: "\n", with: " ")
    if flat.count > limit {
        return String(flat.prefix(limit)) + "…"
    }
    return flat
}

private func journalDateString(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
}

private func monogramJournalEntries(_ entries: [MonogramJournalEntry]) -> [MonogramJournalEntryItem] {
    var result: [MonogramJournalEntryItem] = []
    if entries.isEmpty {
        result.append(.info("Журнал пока пуст. Здесь появятся удалённые и изменённые собеседниками сообщения."))
        return result
    }
    result.append(.info("Нажмите на запись, чтобы перейти к сообщению в чате."))
    var index: Int32 = 0
    for entry in entries.prefix(500) {
        let title: String
        let label: String
        switch entry.kind {
        case .deleted:
            title = "🗑 \(entry.peerTitle)"
            label = "\(shortened(entry.text, limit: 200))\n\(journalDateString(entry.date))"
        case .edited:
            title = "✏️ \(entry.peerTitle)"
            label = "Было: \(shortened(entry.oldText ?? "", limit: 120))\nСтало: \(shortened(entry.text, limit: 120))\n\(journalDateString(entry.date))"
        case .media:
            title = "📎 \(entry.peerTitle)"
            label = "\(entry.text)\n\(journalDateString(entry.date))"
        }
        result.append(.item(index, entry, title, label))
        index += 1
    }
    result.append(.clear(100000, "Очистить журнал"))
    return result
}

public func monogramJournalController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshCounter = 0
    var controllerReference: ViewController?
    
    let arguments = MonogramJournalControllerArguments(open: { entry in
        if entry.kind == .media, let path = entry.oldText, FileManager.default.fileExists(atPath: path), let presenter = controllerReference {
            let documentController = UIDocumentInteractionController(url: URL(fileURLWithPath: path))
            let delegate = MonogramDocumentPreviewDelegate(presenter: presenter)
            documentController.delegate = delegate
            monogramDocumentPreviewHolder = (documentController, delegate)
            documentController.presentPreview(animated: true)
            return
        }
        let peerId = PeerId(entry.peerId)
        let messageId = MessageId(peerId: peerId, namespace: entry.namespace, id: entry.id)
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer, let navigationController = controllerReference?.navigationController as? NavigationController else {
                return
            }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(messageId), highlight: ChatControllerSubject.MessageHighlight(), timecode: nil, setupReply: false)))
        })
    }, clear: {
        MonogramJournal.shared.clear()
        refreshCounter += 1
        refresh.set(refreshCounter)
    })
    
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        refresh.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Журнал"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: monogramJournalEntries(MonogramJournal.shared.entries()), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    controllerReference = controller
    return controller
}
