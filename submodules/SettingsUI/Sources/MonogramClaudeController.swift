import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

struct MonogramClaudeMessage: Equatable {
    let role: String
    let text: String
    var imageBase64: String? = nil
}

final class MonogramPhotoPickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
        super.init()
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        picker.dismiss(animated: true)
        self.completion(image)
        monogramPhotoPickerHolder = nil
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        self.completion(nil)
        monogramPhotoPickerHolder = nil
    }
}

var monogramPhotoPickerHolder: MonogramPhotoPickerDelegate?

/// Уменьшает фото до 1568 px по длинной стороне и кодирует в JPEG base64 (меньше токенов и трафика).
func monogramEncodeImage(_ image: UIImage) -> String? {
    let size = image.size
    if size.width < 1.0 || size.height < 1.0 {
        return nil
    }
    let scale = min(1.0, 1568.0 / max(size.width, size.height))
    let target = CGSize(width: max(1.0, (size.width * scale).rounded()), height: max(1.0, (size.height * scale).rounded()))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1.0
    let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
    return rendered.jpegData(compressionQuality: 0.8)?.base64EncodedString()
}

func monogramClaudeSend(apiKey: String, model: String, effort: String, messages: [MonogramClaudeMessage], completion: @escaping (Result<String, MonogramClaudeError>) -> Void) {
    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
        completion(.failure(MonogramClaudeError(text: "Неверный адрес API")))
        return
    }
    // Настоящее усилие: output_config.effort (GA, без beta-заголовка). Мышление остаётся адаптивным по умолчанию.
    // Если API отклонит этот параметр, запрос один раз повторяется без него.
    var body: [String: Any] = [
        "model": model,
        "max_tokens": 16000,
        "system": "Отвечай на языке пользователя.",
        "output_config": ["effort": effort],
        "messages": messages.enumerated().map { index, message -> [String: Any] in
            // Фото отправляется только в последнем сообщении, в старых остаётся пометка (экономия токенов).
            if let image = message.imageBase64, index == messages.count - 1 {
                return ["role": message.role, "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image]],
                    ["type": "text", "text": message.text]
                ]]
            }
            return ["role": message.role, "content": message.imageBase64 != nil ? "[фото отправлено ранее]\n" + message.text : message.text]
        }
    ]
    var didRetryWithoutEffort = false

    func perform() {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(MonogramClaudeError(text: "Не удалось собрать запрос")))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300.0
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(MonogramClaudeError(text: error.localizedDescription)))
                return
            }
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(MonogramClaudeError(text: "Пустой или нечитаемый ответ")))
                return
            }
            if let errorInfo = json["error"] as? [String: Any] {
                let message = (errorInfo["message"] as? String) ?? "Неизвестная ошибка API"
                if !didRetryWithoutEffort, (response as? HTTPURLResponse)?.statusCode == 400, message.contains("output_config") || message.contains("effort") {
                    didRetryWithoutEffort = true
                    body.removeValue(forKey: "output_config")
                    perform()
                    return
                }
                completion(.failure(MonogramClaudeError(text: message)))
                return
            }
            if (json["stop_reason"] as? String) == "refusal" {
                completion(.failure(MonogramClaudeError(text: "Claude отказался отвечать на этот запрос")))
                return
            }
            monogramClaudeHandleContent(json: json, completion: completion)
        }.resume()
    }
    perform()
}

private func monogramClaudeHandleContent(json: [String: Any], completion: @escaping (Result<String, MonogramClaudeError>) -> Void) {
    guard let content = json["content"] as? [[String: Any]] else {
        completion(.failure(MonogramClaudeError(text: "В ответе нет текста")))
        return
    }
    let text = content.compactMap { block -> String? in
        if (block["type"] as? String) == "text" {
            return block["text"] as? String
        }
        return nil
    }.joined(separator: "\n")
    if text.isEmpty {
        completion(.failure(MonogramClaudeError(text: "Ответ пустой")))
    } else {
        completion(.success(text))
    }
}

struct MonogramClaudeError: Error {
    let text: String
}

private final class MonogramClaudeSettingsArguments {
    let updateKey: (String) -> Void
    let cycleModel: () -> Void
    let cycleEffort: () -> Void
    let clear: () -> Void

    init(updateKey: @escaping (String) -> Void, cycleModel: @escaping () -> Void, cycleEffort: @escaping () -> Void, clear: @escaping () -> Void) {
        self.updateKey = updateKey
        self.cycleModel = cycleModel
        self.cycleEffort = cycleEffort
        self.clear = clear
    }
}

private enum MonogramClaudeSettingsEntry: ItemListNodeEntry {
    case header(Int32, String)
    case info(Int32, String)
    case action(Int32, String)
    case choice(Int32, String, String, Int32)
    case key(Int32, String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        return self.sortIndex
    }

    var sortIndex: Int32 {
        switch self {
        case let .header(index, _), let .info(index, _), let .action(index, _), let .choice(index, _, _, _), let .key(index, _):
            return index
        }
    }

    static func ==(lhs: MonogramClaudeSettingsEntry, rhs: MonogramClaudeSettingsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a, b), .header(c, d)):
            return a == c && b == d
        case let (.info(a, b), .info(c, d)):
            return a == c && b == d
        case let (.action(a, b), .action(c, d)):
            return a == c && b == d
        case let (.choice(a, b, c, d), .choice(e, f, g, h)):
            return a == e && b == f && c == g && d == h
        case let (.key(a, b), .key(c, d)):
            return a == c && b == d
        default:
            return false
        }
    }

    static func <(lhs: MonogramClaudeSettingsEntry, rhs: MonogramClaudeSettingsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MonogramClaudeSettingsArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .action(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clear()
            })
        case let .choice(_, title, label, tag):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                if tag == 0 {
                    arguments.cycleModel()
                } else {
                    arguments.cycleEffort()
                }
            })
        case let .key(_, text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "Ключ API"), text: text, placeholder: "sk-ant-…", type: .password, spacing: 10.0, sectionId: self.section, textUpdated: { value in
                arguments.updateKey(value)
            }, action: {})
        }
    }
}

public func monogramClaudeSettingsController(context: AccountContext, clearHistory: @escaping () -> Void) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshCounter = 0
    let update = {
        refreshCounter += 1
        refresh.set(refreshCounter)
    }

    let arguments = MonogramClaudeSettingsArguments(updateKey: { value in
        MonogramSettings.shared.claudeApiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }, cycleModel: {
        let settings = MonogramSettings.shared
        let models = MonogramSettings.claudeModels
        let index = models.firstIndex(where: { $0.id == settings.claudeModel }) ?? 0
        settings.claudeModel = models[(index + 1) % models.count].id
        update()
    }, cycleEffort: {
        let settings = MonogramSettings.shared
        let efforts = MonogramSettings.claudeEfforts
        let index = efforts.firstIndex(where: { $0.id == settings.claudeEffort }) ?? 0
        settings.claudeEffort = efforts[(index + 1) % efforts.count].id
        update()
    }, clear: {
        clearHistory()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        refresh.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = MonogramSettings.shared
        let modelTitle = MonogramSettings.claudeModels.first(where: { $0.id == settings.claudeModel })?.title ?? settings.claudeModel
        let effortTitle = MonogramSettings.claudeEfforts.first(where: { $0.id == settings.claudeEffort })?.title ?? settings.claudeEffort
        var entries: [MonogramClaudeSettingsEntry] = []
        entries.append(.header(0, "НАСТРОЙКИ"))
        entries.append(.key(1, settings.claudeApiKey))
        entries.append(.choice(2, "Модель", modelTitle, 0))
        entries.append(.choice(3, "Усилие", effortTitle, 1))
        entries.append(.info(4, "Ключ хранится только на этом устройстве и отправляется только на api.anthropic.com. Текст запросов оплачивается с вашего баланса Anthropic. «Усилие» — параметр effort API: чем выше, тем глубже рассуждение модели, дольше ответ и больше расход токенов."))
        entries.append(.action(5, "Очистить диалог"))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Настройки Claude"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
