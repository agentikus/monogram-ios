import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

private let monogramClaudeHistoryKey = "monogram_claudeHistory"
private let monogramClaudeHistoryLimit = 80

private enum MonogramClaudeRow {
    case message(MonogramClaudeMessage)
    case typing
    case error(String)
}

private final class MonogramClaudeBubbleCell: UITableViewCell, UIContextMenuInteractionDelegate {
    static let reuseId = "bubble"

    private let bubble = UIView()
    private let label = UILabel()
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var copyText: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none

        self.bubble.translatesAutoresizingMaskIntoConstraints = false
        self.bubble.layer.cornerRadius = 18.0
        self.contentView.addSubview(self.bubble)

        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.label.numberOfLines = 0
        self.label.font = UIFont.systemFont(ofSize: 16.0)
        self.bubble.addSubview(self.label)

        self.leadingConstraint = self.bubble.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 10.0)
        self.trailingConstraint = self.bubble.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -10.0)
        let maxWidth = self.bubble.widthAnchor.constraint(lessThanOrEqualTo: self.contentView.widthAnchor, multiplier: 0.82)

        NSLayoutConstraint.activate([
            self.bubble.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 3.0),
            self.bubble.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -3.0),
            maxWidth,
            self.label.topAnchor.constraint(equalTo: self.bubble.topAnchor, constant: 8.0),
            self.label.bottomAnchor.constraint(equalTo: self.bubble.bottomAnchor, constant: -8.0),
            self.label.leadingAnchor.constraint(equalTo: self.bubble.leadingAnchor, constant: 13.0),
            self.label.trailingAnchor.constraint(equalTo: self.bubble.trailingAnchor, constant: -13.0)
        ])

        self.bubble.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, outgoing: Bool, italic: Bool, bubbleColor: UIColor, textColor: UIColor) {
        self.copyText = italic ? nil : text
        self.label.text = text
        self.label.font = italic ? UIFont.italicSystemFont(ofSize: 15.0) : UIFont.systemFont(ofSize: 16.0)
        self.label.textColor = textColor
        self.bubble.backgroundColor = bubbleColor
        self.leadingConstraint.isActive = !outgoing
        self.trailingConstraint.isActive = outgoing
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let text = self.copyText else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            return UIMenu(children: [
                UIAction(title: "Копировать", image: UIImage(systemName: "doc.on.doc"), handler: { _ in
                    UIPasteboard.general.string = text
                })
            ])
        })
    }
}

private func monogramClaudeLoadHistory() -> [MonogramClaudeMessage] {
    guard let data = UserDefaults.standard.data(forKey: monogramClaudeHistoryKey),
          let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
        return []
    }
    return raw.compactMap { item -> MonogramClaudeMessage? in
        guard let role = item["role"], let text = item["text"] else {
            return nil
        }
        return MonogramClaudeMessage(role: role, text: text)
    }
}

private func monogramClaudeSaveHistory(_ messages: [MonogramClaudeMessage]) {
    let raw = messages.suffix(monogramClaudeHistoryLimit).map { ["role": $0.role, "text": $0.text] }
    if let data = try? JSONSerialization.data(withJSONObject: raw) {
        UserDefaults.standard.set(data, forKey: monogramClaudeHistoryKey)
    }
}

private final class MonogramClaudeChatNode: ASDisplayNode, UITableViewDataSource, UITextViewDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputBar = UIView()
    private let separator = UIView()
    private let fieldBackground = UIView()
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let photoButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)

    private var messages: [MonogramClaudeMessage]
    private var isLoading = false
    private var errorText: String?
    private var pendingImage: String?
    private var rows: [MonogramClaudeRow] = []

    private var validLayout: (ContainerViewLayout, CGFloat)?
    private var textHeight: CGFloat = 36.0

    init(context: AccountContext, presentationData: PresentationData) {
        self.context = context
        self.presentationData = presentationData
        self.messages = monogramClaudeLoadHistory()
        super.init()
        self.setViewBlock({
            return UIView()
        })
    }

    override func didLoad() {
        super.didLoad()

        self.tableView.dataSource = self
        self.tableView.separatorStyle = .none
        self.tableView.backgroundColor = .clear
        self.tableView.keyboardDismissMode = .interactive
        self.tableView.allowsSelection = false
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 44.0
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.register(MonogramClaudeBubbleCell.self, forCellReuseIdentifier: MonogramClaudeBubbleCell.reuseId)
        self.view.addSubview(self.tableView)

        self.view.addSubview(self.inputBar)
        self.inputBar.addSubview(self.separator)
        self.inputBar.addSubview(self.fieldBackground)

        self.textView.delegate = self
        self.textView.font = UIFont.systemFont(ofSize: 16.0)
        self.textView.backgroundColor = .clear
        self.textView.textContainerInset = UIEdgeInsets(top: 8.0, left: 8.0, bottom: 8.0, right: 4.0)
        self.textView.isScrollEnabled = true
        self.textView.returnKeyType = .default
        self.fieldBackground.addSubview(self.textView)

        self.placeholder.text = "Сообщение"
        self.placeholder.font = UIFont.systemFont(ofSize: 16.0)
        self.placeholder.isUserInteractionEnabled = false
        self.fieldBackground.addSubview(self.placeholder)

        self.photoButton.addTarget(self, action: #selector(self.photoPressed), for: .touchUpInside)
        self.inputBar.addSubview(self.photoButton)
        self.sendButton.addTarget(self, action: #selector(self.sendPressed), for: .touchUpInside)
        self.inputBar.addSubview(self.sendButton)

        self.applyTheme()
        self.reloadRows(scroll: false)
        self.updateControls()
    }

    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        if self.isNodeLoaded {
            self.applyTheme()
            self.tableView.reloadData()
        }
    }

    private func applyTheme() {
        let theme = self.presentationData.theme
        self.backgroundColor = theme.list.plainBackgroundColor
        self.inputBar.backgroundColor = theme.rootController.navigationBar.opaqueBackgroundColor
        self.separator.backgroundColor = theme.rootController.navigationBar.separatorColor
        self.fieldBackground.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.fieldBackground.layer.cornerRadius = 18.0
        self.fieldBackground.layer.borderWidth = 0.5
        self.fieldBackground.layer.borderColor = theme.rootController.navigationBar.separatorColor.cgColor
        self.textView.textColor = theme.list.itemPrimaryTextColor
        self.textView.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        self.placeholder.textColor = theme.list.itemPlaceholderTextColor
        self.photoButton.tintColor = theme.list.itemAccentColor
        self.sendButton.tintColor = theme.list.itemAccentColor
    }

    private func updateControls() {
        let hasText = !self.textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.placeholder.isHidden = !self.textView.text.isEmpty
        let canSend = (hasText || self.pendingImage != nil) && !self.isLoading
        self.sendButton.isEnabled = canSend
        self.sendButton.alpha = canSend ? 1.0 : 0.4
        let config = UIImage.SymbolConfiguration(pointSize: 26.0, weight: .regular)
        self.sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config), for: .normal)
        let photoName = self.pendingImage == nil ? "photo" : "photo.fill"
        let photoConfig = UIImage.SymbolConfiguration(pointSize: 22.0, weight: .regular)
        self.photoButton.setImage(UIImage(systemName: photoName, withConfiguration: photoConfig), for: .normal)
    }

    private func reloadRows(scroll: Bool) {
        var rows: [MonogramClaudeRow] = self.messages.map { .message($0) }
        if self.isLoading {
            rows.append(.typing)
        }
        if let error = self.errorText {
            rows.append(.error(error))
        }
        self.rows = rows
        self.tableView.reloadData()
        if scroll {
            self.scrollToBottom(animated: false)
        }
    }

    private func scrollToBottom(animated: Bool) {
        if self.rows.isEmpty {
            return
        }
        self.tableView.layoutIfNeeded()
        let index = IndexPath(row: self.rows.count - 1, section: 0)
        self.tableView.scrollToRow(at: index, at: .bottom, animated: animated)
    }

    // MARK: - Layout

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let previousInput = self.validLayout?.0.inputHeight ?? 0.0
        self.validLayout = (layout, navigationBarHeight)
        guard self.isNodeLoaded else {
            return
        }
        let size = layout.size
        let bottomInset = max(layout.intrinsicInsets.bottom, layout.inputHeight ?? 0.0)
        let left = layout.safeInsets.left
        let right = layout.safeInsets.right

        let buttonSize: CGFloat = 40.0
        let fieldLeft = left + 8.0 + buttonSize
        let fieldWidth = max(60.0, size.width - fieldLeft - right - 8.0 - buttonSize)
        let fitting = self.textView.sizeThatFits(CGSize(width: fieldWidth, height: CGFloat.greatestFiniteMagnitude)).height
        self.textHeight = min(120.0, max(36.0, fitting))

        let barHeight = self.textHeight + 12.0
        let barFrame = CGRect(x: 0.0, y: size.height - bottomInset - barHeight, width: size.width, height: barHeight + bottomInset)

        transition.updateFrame(view: self.inputBar, frame: barFrame)
        self.separator.frame = CGRect(x: 0.0, y: 0.0, width: size.width, height: 0.5)
        self.fieldBackground.frame = CGRect(x: fieldLeft, y: 6.0, width: fieldWidth, height: self.textHeight)
        self.textView.frame = CGRect(origin: .zero, size: CGSize(width: fieldWidth, height: self.textHeight))
        self.placeholder.sizeToFit()
        self.placeholder.frame = CGRect(x: 14.0, y: floor((self.textHeight - self.placeholder.bounds.height) / 2.0), width: self.placeholder.bounds.width, height: self.placeholder.bounds.height)
        self.photoButton.frame = CGRect(x: left + 4.0, y: barHeight - 6.0 - buttonSize + (buttonSize - 36.0) / 2.0 - 2.0, width: buttonSize, height: buttonSize)
        self.sendButton.frame = CGRect(x: size.width - right - 4.0 - buttonSize, y: barHeight - 6.0 - buttonSize + (buttonSize - 36.0) / 2.0 - 2.0, width: buttonSize, height: buttonSize)

        transition.updateFrame(view: self.tableView, frame: CGRect(x: 0.0, y: 0.0, width: size.width, height: barFrame.minY))
        self.tableView.contentInset = UIEdgeInsets(top: navigationBarHeight + 4.0, left: 0.0, bottom: 4.0, right: 0.0)
        self.tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: navigationBarHeight, left: 0.0, bottom: 0.0, right: 0.0)

        if abs(previousInput - (layout.inputHeight ?? 0.0)) > 1.0 {
            self.scrollToBottom(animated: false)
        }
    }

    private func relayout() {
        if let (layout, navigationBarHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
        }
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MonogramClaudeBubbleCell.reuseId, for: indexPath) as! MonogramClaudeBubbleCell
        let theme = self.presentationData.theme
        switch self.rows[indexPath.row] {
        case let .message(message):
            let outgoing = message.role == "user"
            let text = (message.imageBase64 != nil ? "📷 " : "") + message.text
            cell.configure(text: text, outgoing: outgoing, italic: false, bubbleColor: outgoing ? theme.list.itemAccentColor : theme.list.itemBlocksBackgroundColor, textColor: outgoing ? UIColor.white : theme.list.itemPrimaryTextColor)
        case .typing:
            cell.configure(text: "Claude печатает…", outgoing: false, italic: true, bubbleColor: theme.list.itemBlocksBackgroundColor, textColor: theme.list.itemSecondaryTextColor)
        case let .error(text):
            cell.configure(text: "Ошибка: \(text)", outgoing: false, italic: true, bubbleColor: theme.list.itemBlocksBackgroundColor, textColor: theme.list.itemDestructiveColor)
        }
        return cell
    }

    // MARK: - Input

    func textViewDidChange(_ textView: UITextView) {
        self.updateControls()
        self.relayout()
    }

    @objc private func photoPressed() {
        if self.pendingImage != nil {
            self.pendingImage = nil
            self.updateControls()
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        let delegate = MonogramPhotoPickerDelegate(completion: { [weak self] image in
            guard let self else {
                return
            }
            if let image = image, let encoded = monogramEncodeImage(image) {
                self.pendingImage = encoded
                self.errorText = nil
            } else if image != nil {
                self.errorText = "не удалось подготовить фото"
            }
            self.reloadRows(scroll: true)
            self.updateControls()
        })
        monogramPhotoPickerHolder = delegate
        picker.delegate = delegate
        self.context.sharedContext.mainWindow?.presentNative(picker)
    }

    @objc private func sendPressed() {
        let settings = MonogramSettings.shared
        let image = self.pendingImage
        let rawText = self.textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawText.isEmpty && image == nil || self.isLoading {
            return
        }
        let text = rawText.isEmpty ? "Что на фото?" : rawText
        if settings.claudeApiKey.isEmpty {
            self.errorText = "введите ключ API в настройках (кнопка вверху справа)"
            self.reloadRows(scroll: true)
            return
        }
        self.errorText = nil
        self.messages.append(MonogramClaudeMessage(role: "user", text: text, imageBase64: image))
        self.textView.text = ""
        self.pendingImage = nil
        self.isLoading = true
        self.reloadRows(scroll: true)
        self.updateControls()
        self.relayout()
        monogramClaudeSaveHistory(self.messages)

        monogramClaudeSend(apiKey: settings.claudeApiKey, model: settings.claudeModel, effort: settings.claudeEffort, messages: self.messages, completion: { [weak self] result in
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                self.isLoading = false
                switch result {
                case let .success(answer):
                    self.messages.append(MonogramClaudeMessage(role: "assistant", text: answer))
                    settings.claudeLastPreview = String(answer.prefix(200)).replacingOccurrences(of: "\n", with: " ")
                    settings.claudeLastTimestamp = Int32(Date().timeIntervalSince1970)
                    monogramClaudeSaveHistory(self.messages)
                case let .failure(error):
                    if self.messages.last?.role == "user" {
                        let failed = self.messages.removeLast()
                        self.textView.text = failed.text
                        self.pendingImage = failed.imageBase64
                    }
                    self.errorText = error.text
                    monogramClaudeSaveHistory(self.messages)
                }
                self.reloadRows(scroll: true)
                self.updateControls()
                self.relayout()
            }
        })
    }

    func clearHistory() {
        self.messages = []
        self.errorText = nil
        monogramClaudeSaveHistory([])
        MonogramSettings.shared.claudeLastPreview = ""
        MonogramSettings.shared.claudeLastTimestamp = 0
        if self.isNodeLoaded {
            self.reloadRows(scroll: false)
        }
    }

    func dismissKeyboard() {
        if self.isNodeLoaded {
            self.textView.resignFirstResponder()
        }
    }
}

private final class MonogramClaudeChatController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    private var chatNode: MonogramClaudeChatNode {
        return self.displayNode as! MonogramClaudeChatNode
    }

    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData, style: .glass))

        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.title = "Claude"
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Настройки", style: .plain, target: self, action: #selector(self.settingsPressed))

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            self.presentationData = presentationData
            self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData, style: .glass), transition: .immediate)
            if self.isNodeLoadedSafe {
                self.chatNode.updatePresentationData(presentationData)
            }
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    private var isNodeLoadedSafe: Bool {
        return self.isViewLoaded
    }

    override func loadDisplayNode() {
        self.displayNode = MonogramClaudeChatNode(context: self.context, presentationData: self.presentationData)
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.chatNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.chatNode.dismissKeyboard()
    }

    @objc private func settingsPressed() {
        self.chatNode.dismissKeyboard()
        let controller = monogramClaudeSettingsController(context: self.context, clearHistory: { [weak self] in
            self?.chatNode.clearHistory()
        })
        self.push(controller)
    }
}

public func monogramClaudeController(context: AccountContext) -> ViewController {
    return MonogramClaudeChatController(context: context)
}
