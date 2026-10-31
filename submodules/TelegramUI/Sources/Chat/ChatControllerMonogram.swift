import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import AlertUI
import PresentationDataUtils

extension ChatControllerImpl {
    func monogramConfirmSend(text: String, send: @escaping () -> Void) {
        let alertController = textAlertController(
            context: self.context,
            updatedPresentationData: self.updatedPresentationData,
            title: nil,
            text: text,
            actions: [
                TextAlertAction(type: .genericAction, title: self.presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .defaultAction, title: "Отправить", action: {
                    send()
                })
            ]
        )
        self.present(alertController, in: .window(.root))
    }
}
