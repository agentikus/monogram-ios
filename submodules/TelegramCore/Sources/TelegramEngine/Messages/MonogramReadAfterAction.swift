import Foundation
import Postbox
import SwiftSignalKit

public extension TelegramEngine.Messages {
    func monogramMarkReadAfterAction(peerId: EnginePeer.Id) -> Signal<Never, NoError> {
        if MonogramSettings.shared.sendReadMessages || !MonogramSettings.shared.markReadAfterAction {
            return .complete()
        }
        let account = self.account
        let rawPeerId = peerId.toInt64()
        let pushSignal = synchronizePeerReadState(network: account.network, postbox: account.postbox, stateManager: account.stateManager, peerId: peerId, push: true, validate: false)
        |> `catch` { _ -> Signal<Never, NoError> in
            return .complete()
        }
        return Signal { subscriber in
            MonogramSettings.shared.setReadPushAllowed(rawPeerId, true)
            let disposable = pushSignal.start(completed: {
                MonogramSettings.shared.setReadPushAllowed(rawPeerId, false)
                subscriber.putCompletion()
            })
            return ActionDisposable {
                disposable.dispose()
                MonogramSettings.shared.setReadPushAllowed(rawPeerId, false)
            }
        }
    }
}
