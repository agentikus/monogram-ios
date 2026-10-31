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
}

private final class MonogramClaudeState {
    var messages: [MonogramClaudeMessage] = []
    var input: String = ""
    var isLoading = false
    var error: String?
}

private final class MonogramClaudeArguments {
    let updateInput: (String) -> Void
    let updateKey: (String) -> Void
    let send: () -> Void
    let clear: () -> Void
    let copyLast: () -> Void
    let cycleModel: () -> Void
    let cycleEffort: () -> Void

    init(updateInput: @escaping (String) -> Void, updateKey: @escaping (String) -> Void, send: @escaping () -> Void, clear: @escaping () -> Void, copyLast: @escaping () -> Void, cycleModel: @escaping () -> Void, cycleEffort: @escaping () -> Void) {
        self.updateInput = updateInput
        self.updateKey = updateKey
        self.send = send
        self.clear = clear
        self.copyLast = copyLast
        self.cycleModel = cycleModel
        self.cycleEffort = cycleEffort
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
                if tag == 1 {
                    arguments.clear()
                } else {
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
        entries.append(.info(1, "Задайте вопрос ниже. История хранится только на экране и пропадает при закрытии."))
    }
    for (index, message) in state.messages.enumerated() {
        entries.append(.message(10 + Int32(index), message.role == "user" ? "Вы" : "Claude", message.text))
    }
    if state.isLoading {
        entries.append(.info(900, "Claude отвечает…"))
    }
    if let error = state.error {
        entries.append(.info(901, "Ошибка: \(error)"))
    }

    entries.append(.input(1000, state.input))
    entries.append(.send(1001, state.isLoading ? "Отправка…" : "Отправить", state.isLoading))
    if state.messages.last?.role == "assistant" {
        entries.append(.action(1002, "Скопировать последний ответ", 0))
    }
    if !state.messages.isEmpty {
        entries.append(.action(1003, "Очистить диалог", 1))
    }

    let modelTitle = MonogramSettings.claudeModels.first(where: { $0.id == settings.claudeModel })?.title ?? settings.claudeModel
    let effortTitle = MonogramSettings.claudeEfforts.first(where: { $0.id == settings.claudeEffort })?.title ?? settings.claudeEffort
    entries.append(.header(2000, "НАСТРОЙКИ"))
    entries.append(.key(2001, settings.claudeApiKey))
    entries.append(.choice(2002, "Модель", modelTitle, 0))
    entries.append(.choice(2003, "Усилие", effortTitle, 1))
    entries.append(.info(2004, "Ключ хранится только на этом устройстве и отправляется только на api.anthropic.com. Текст запросов оплачивается с вашего баланса Anthropic. «Усилие» задаёт подробность и длину ответа: низкое — коротко, высокое — подробно с рассуждением."))

    return entries
}

private func monogramClaudeSend(apiKey: String, model: String, effort: String, messages: [MonogramClaudeMessage], completion: @escaping (Result<String, MonogramClaudeError>) -> Void) {
    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
        completion(.failure(MonogramClaudeError(text: "Неверный адрес API")))
        return
    }
    let maxTokens: Int
    let system: String
    switch effort {
    case "high":
        maxTokens = 4096
        system = "Рассуждай тщательно, проверяй себя, затем дай подробный и точный ответ. Отвечай на языке пользователя."
    case "medium":
        maxTokens = 2048
        system = "Отвечай развёрнуто, но по делу. Отвечай на языке пользователя."
    default:
        maxTokens = 1024
        system = "Отвечай кратко. Отвечай на языке пользователя."
    }
    let body: [String: Any] = [
        "model": model,
        "max_tokens": maxTokens,
        "system": system,
        "messages": messages.map { ["role": $0.role, "content": $0.text] }
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else {
        completion(.failure(MonogramClaudeError(text: "Не удалось собрать запрос")))
        return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 120.0
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
            completion(.failure(MonogramClaudeError(text: (errorInfo["message"] as? String) ?? "Неизвестная ошибка API")))
            return
        }
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
    }.resume()
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
        let text = state.input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return
        }
        if settings.claudeApiKey.isEmpty {
            state.error = "введите ключ API в настройках ниже"
            update()
            return
        }
        state.error = nil
        state.messages.append(MonogramClaudeMessage(role: "user", text: text))
        state.input = ""
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
