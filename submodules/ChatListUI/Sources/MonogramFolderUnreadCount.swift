import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext

private func isSignaFolderTitle(_ title: String) -> Bool {
    let lowercased = title.lowercased()
    return false
}

private func isChatMuted(transaction: Transaction, peer: Peer, globalSettings: GlobalNotificationSettingsSet) -> Bool {
    if let notificationSettings = transaction.getPeerNotificationSettings(id: peer.id) as? TelegramPeerNotificationSettings {
        switch notificationSettings.muteState {
        case .muted:
            return true
        case .unmuted:
            return false
        case .default:
            break
        }
    }
    if peer is TelegramUser {
        return !globalSettings.privateChats.enabled
    } else if peer is TelegramGroup {
        return !globalSettings.groupChats.enabled
    } else if let channel = peer as? TelegramChannel {
        switch channel.info {
        case .group:
            return !globalSettings.groupChats.enabled
        case .broadcast:
            return !globalSettings.channels.enabled
        }
    }
    return false
}

public func monogramFolderExtraUnreadCount(context: AccountContext) -> Signal<Int32, NoError> {
    let accountPeerId = context.account.peerId
    let unreadKey: PostboxViewKey = .unreadCounts(items: [.totalInGroup(.root), .totalInGroup(Namespaces.PeerGroup.archive)])
    return combineLatest(
        context.engine.peers.updatedChatListFilters() |> distinctUntilChanged,
        context.account.postbox.combinedView(keys: [unreadKey]) |> map { _ -> Void in return Void() }
    )
    |> mapToSignal { filters, _ -> Signal<Int32, NoError> in
        var folders: [ChatListFilterData] = []
        for filter in filters {
            if case let .filter(_, title, _, data) = filter, isSignaFolderTitle(title.text) {
                folders.append(data)
            }
        }
        if folders.isEmpty {
            return .single(0)
        }
        return context.account.postbox.transaction { transaction -> Int32 in
            let globalSettings = transaction.getPreferencesEntry(key: PreferencesKeys.globalNotifications)?.get(GlobalNotificationSettings.self)?.effective ?? GlobalNotificationSettings.defaultSettings.effective
            var counted = Set<PeerId>()
            var total: Int32 = 0
            for data in folders {
                let predicate = chatListFilterPredicate(filter: data, accountPeerId: accountPeerId)
                for groupId in [PeerGroupId.root, Namespaces.PeerGroup.archive] {
                    for peerId in transaction.getUnreadChatListPeerIds(groupId: groupId, filterPredicate: predicate, additionalFilter: nil, stopOnFirstMatch: false) {
                        if counted.contains(peerId) {
                            continue
                        }
                        guard let peer = transaction.getPeer(peerId) else {
                            continue
                        }
                        if groupId == .root && !isChatMuted(transaction: transaction, peer: peer, globalSettings: globalSettings) {
                            continue
                        }
                        counted.insert(peerId)
                        total += max(1, transaction.getCombinedPeerReadState(peerId)?.count ?? 0)
                    }
                }
            }
            return total
        }
    }
    |> distinctUntilChanged
}
