import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private struct MonogramClaudeMessage: Equatable {
    let role: String
    let text: String
    var imageBase64: String? = nil
}

private final class MonogramPhotoPickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
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

private var monogramPhotoPickerHolder: MonogramPhotoPickerDelegate?

/// Уменьшает фото до 1568 px по длинной стороне и кодирует в JPEG base64 (меньше токенов и трафика).
private func monogramEncodeImage(_ image: UIImage) -> String? {
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

private final class MonogramClaudeState {
    var messages: [MonogramClaudeMessage] = []
    var input: String = ""
    var isLoading = false
    var error: String?
    var pendingImage: String?
}

private final class MonogramClaudeArguments {
    let updateInput: (String) -> Void
    let updateKey: (String) -> Void
    let send: () -> Void
    let clear: () -> Void
    let copyLast: () -> Void
    let cycleModel: () -> Void
    let cycleEffort: () -> Void
    let pickPhoto: () -> Void
    let removePhoto: () -> Void

    init(updateInput: @escaping (String) -> Void, updateKey: @escaping (String) -> Void, send: @escaping () -> Void, clear: @escaping () -> Void, copyLast: @escaping () -> Void, cycleModel: @escaping () -> Void, cycleEffort: @escaping () -> Void, pickPhoto: @escaping () -> Void, removePhoto: @escaping () -> Void) {
        self.updateInput = updateInput
        self.updateKey = updateKey
        self.send = send
        self.clear = clear
        self.copyLast = copyLast
        self.cycleModel = cycleModel
        self.cycleEffort = cycleEffort
        self.pickPhoto = pickPhoto
        self.removePhoto = removePhoto
    }
}

private enum MonogramClaudeEntry: ItemListNodeEntry {
    case header(Int32, String)
    case message(Int32, String, String)
    case info(Int32, String)
    case input(Int32, String)
    case send(Int32, String, Bool)
    case action(Int32, String, Int32)
    case choice(Int32, String, String, Int32)
    case key(Int32, String)

    var section: ItemListSectionId {
        return self.sortIndex / 1000
    }

    var stableId: Int32 {
        return self.sortIndex
    }

    var sortIndex: Int32 {
        switch self {
        case let .header(index, _), let .message(index, _, _), let .info(index, _), let .input(index, _), let .send(index, _, _), let .action(index, _, _), let .choice(index, _, _, _), let .key(index, _):
            return index
        }
    }

    static func ==(lhs: MonogramClaudeEntry, rhs: MonogramClaudeEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a, b), .header(c, d)):
            return a == c && b == d
        case let (.message(a, b, c), .message(d, e, f)):
            return a == d && b == e && c == f
        case let (.info(a, b), .info(c, d)):
            return a == c && b == d
        case let (.input(a, b), .input(c, d)):
            return a == c && b == d
        case let (.send(a, b, c), .send(d, e, f)):
            return a == d && b == e && c == f
        case let (.action(a, b, c), .action(d, e, f)):
            return a == d && b == e && c == f
        case let (.choice(a, b, c, d), .choice(e, f, g, h)):
            return a == e && b == f && c == g && d == h
        case let (.key(a, b), .key(c, d)):
            return a == c && b == d
        default:
            return false
        }
    }

    static func <(lhs: MonogramClaudeEntry, rhs: MonogramClaudeEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MonogramClaudeArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .message(_, role, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain("\(role)\n\(text)"), sectionId: self.section, textSize: .larger)
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .input(_, text):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: "Сообщение для Claude", maxLength: nil, sectionId: self.section, style: .blocks, textUpdated: { value in
                arguments.updateInput(value)
            })
        case let .send(_, title, isLoading):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: isLoading ? .disabled : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if !isLoading {
                    arguments.send()
                }
            })
        case let .action(_, title, tag):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: tag == 1 ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                switch tag {
                case 1:
                    arguments.clear()
                case 2:
                    arguments.pickPhoto()
                case 3:
                    arguments.removePhoto()
                default:
                    arguments.copyLast()
                }
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

private func monogramClaudeEntries(state: MonogramClaudeState) -> [MonogramClaudeEntry] {
    let settings = MonogramSettings.shared
    var entries: [MonogramClaudeEntry] = []

    entries.append(.header(0, "ДИАЛОГ"))
    if state.messages.isEmpty {
        entries.append(.info(1, "Задайте вопрос ниже, при желании прикрепив фото. История хранится только на экране и пропадает при закрытии. Фото отправляется только вместе с тем сообщением, к которому прикреплено."))
    }
    for (index, message) in state.messages.enumerated() {
        entries.append(.message(10 + Int32(index), message.role == "user" ? "Вы" : "Claude", (message.imageBase64 != nil ? "📷 " : "") + message.text))
    }
    if state.isLoading {
        entries.append(.info(900, "Claude отвечает…"))
    }
    if let error = state.error {
        entries.append(.info(901, "Ошибка: \(error)"))
    }

    entries.append(.input(1000, state.input))
    if state.pendingImage == nil {
        entries.append(.action(1001, "Прикрепить фото", 2))
    } else {
        entries.append(.action(1001, "Фото прикреплено — убрать", 3))
    }
    entries.append(.send(1002, state.isLoading ? "Отправка…" : "Отправить", state.isLoading))
    if state.messages.last?.role == "assistant" {
        entries.append(.action(1003, "Скопировать последний ответ", 0))
    }
    if !state.messages.isEmpty {
        entries.append(.action(1004, "Очистить диалог", 1))
    }

    let modelTitle = MonogramSettings.claudeModels.first(where: { $0.id == settings.claudeModel })?.title ?? settings.claudeModel
    let effortTitle = MonogramSettings.claudeEfforts.first(where: { $0.id == settings.claudeEffort })?.title ?? settings.claudeEffort
    entries.append(.header(2000, "НАСТРОЙКИ"))
    entries.append(.key(2001, settings.claudeApiKey))
    entries.append(.choice(2002, "Модель", modelTitle, 0))
    entries.append(.choice(2003, "Усилие", effortTitle, 1))
    entries.append(.info(2004, "Ключ хранится только на этом устройстве и отправляется только на api.anthropic.com. Текст запросов оплачивается с вашего баланса Anthropic. «Усилие» — параметр effort API: чем выше, тем глубже рассуждение модели, дольше ответ и больше расход токенов."))

    return entries
}

private func monogramClaudeSend(apiKey: String, model: String, effort: String, messages: [MonogramClaudeMessage], completion: @escaping (Result<String, MonogramClaudeError>) -> Void) {
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

private struct MonogramClaudeError: Error {
    let text: String
}

public func monogramClaudeController(context: AccountContext) -> ViewController {
    let state = MonogramClaudeState()
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var refreshCounter = 0
    let update = {
        refreshCounter += 1
        refresh.set(refreshCounter)
    }

    let arguments = MonogramClaudeArguments(updateInput: { value in
        state.input = value
    }, updateKey: { value in
        MonogramSettings.shared.claudeApiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }, send: {
        let settings = MonogramSettings.shared
        let image = state.pendingImage
        let rawText = state.input.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawText.isEmpty && image == nil {
            return
        }
        let text = rawText.isEmpty ? "Что на фото?" : rawText
        if settings.claudeApiKey.isEmpty {
            state.error = "введите ключ API в настройках ниже"
            update()
            return
        }
        state.error = nil
        state.messages.append(MonogramClaudeMessage(role: "user", text: text, imageBase64: image))
        state.input = ""
        state.pendingImage = nil
        state.isLoading = true
        update()
        monogramClaudeSend(apiKey: settings.claudeApiKey, model: settings.claudeModel, effort: settings.claudeEffort, messages: state.messages, completion: { result in
            Queue.mainQueue().async {
                state.isLoading = false
                switch result {
                case let .success(answer):
                    state.messages.append(MonogramClaudeMessage(role: "assistant", text: answer))
                case let .failure(error):
                    state.messages.removeLast()
                    state.input = text
                    state.pendingImage = image
                    state.error = error.text
                }
                update()
            }
        })
    }, clear: {
        state.messages = []
        state.error = nil
        update()
    }, copyLast: {
        if let last = state.messages.last(where: { $0.role == "assistant" }) {
            UIPasteboard.general.string = last.text
        }
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
    }, pickPhoto: {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        let delegate = MonogramPhotoPickerDelegate(completion: { image in
            if let image = image, let encoded = monogramEncodeImage(image) {
                state.pendingImage = encoded
                state.error = nil
            } else if image != nil {
                state.error = "не удалось подготовить фото"
            }
            update()
        })
        monogramPhotoPickerHolder = delegate
        picker.delegate = delegate
        context.sharedContext.mainWindow?.presentNative(picker)
    }, removePhoto: {
        state.pendingImage = nil
        update()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        refresh.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Claude"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: monogramClaudeEntries(state: state), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
