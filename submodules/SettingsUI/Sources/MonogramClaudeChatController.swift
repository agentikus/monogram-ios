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
    case message(MonogramClaudeMessage, Int32)
    case typing
    case error(String)
}

private let monogramClaudeTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

private func monogramClaudeTimeText(_ timestamp: Int32) -> String {
    if timestamp <= 0 {
        return ""
    }
    return monogramClaudeTimeFormatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
}

/// Цвета фона чата из обоев, выбранных в настройках (цвет, градиент или фон узорных обоев).
private func monogramClaudeWallpaperColors(_ wallpaper: TelegramWallpaper, theme: PresentationTheme) -> [UIColor] {
    var values: [UInt32] = []
    switch wallpaper {
    case let .color(value):
        values = [value]
    case let .gradient(gradient):
        values = gradient.colors
    case let .file(file):
        values = file.settings.colors
    case let .image(_, settings):
        values = settings.colors
    case let .builtin(settings):
        values = settings.colors
    case .emoticon:
        break
    }
    if values.isEmpty {
        return [theme.list.plainBackgroundColor]
    }
    return values.map { UIColor(rgb: $0) }
}

private final class MonogramClaudeBubbleView: UIView {
    override class var layerClass: AnyClass {
        return CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        return self.layer as! CAGradientLayer
    }

    func setFill(_ colors: [UIColor]) {
        if colors.count > 1 {
            self.gradientLayer.colors = colors.map { $0.cgColor }
            self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
            self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
            self.backgroundColor = nil
        } else {
            self.gradientLayer.colors = nil
            self.backgroundColor = colors.first ?? UIColor.darkGray
        }
    }
}

private final class MonogramClaudeBubbleCell: UITableViewCell, UIContextMenuInteractionDelegate {
    static let reuseId = "bubble"

    private let bubble = MonogramClaudeBubbleView()
    private let label = UILabel()
    private let timeLabel = UILabel()
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var copyText: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none

        self.bubble.translatesAutoresizingMaskIntoConstraints = false
        self.bubble.layer.cornerRadius = 18.0
        self.bubble.clipsToBounds = true
        self.contentView.addSubview(self.bubble)

        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.label.numberOfLines = 0
        self.label.font = UIFont.systemFont(ofSize: 16.0)
        self.bubble.addSubview(self.label)

        self.timeLabel.translatesAutoresizingMaskIntoConstraints = false
        self.timeLabel.font = UIFont.systemFont(ofSize: 11.0)
        self.timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        self.bubble.addSubview(self.timeLabel)

        self.leadingConstraint = self.bubble.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 10.0)
        self.trailingConstraint = self.bubble.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -10.0)
        let maxWidth = self.bubble.widthAnchor.constraint(lessThanOrEqualTo: self.contentView.widthAnchor, multiplier: 0.82)

        NSLayoutConstraint.activate([
            self.bubble.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 2.0),
            self.bubble.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -2.0),
            maxWidth,
            self.bubble.widthAnchor.constraint(greaterThanOrEqualToConstant: 72.0),
            self.label.topAnchor.constraint(equalTo: self.bubble.topAnchor, constant: 7.0),
            self.label.bottomAnchor.constraint(equalTo: self.bubble.bottomAnchor, constant: -7.0),
            self.label.leadingAnchor.constraint(equalTo: self.bubble.leadingAnchor, constant: 12.0),
            self.label.trailingAnchor.constraint(equalTo: self.bubble.trailingAnchor, constant: -12.0),
            self.timeLabel.trailingAnchor.constraint(equalTo: self.bubble.trailingAnchor, constant: -10.0),
            self.timeLabel.bottomAnchor.constraint(equalTo: self.bubble.bottomAnchor, constant: -5.0)
        ])

        self.bubble.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, time: String, outgoing: Bool, italic: Bool, fill: [UIColor], textColor: UIColor, timeColor: UIColor, checkColor: UIColor?) {
        self.copyText = italic ? nil : text
        // Место под время в последней строке: оно рисуется поверх этих неразрывных пробелов.
        let reserve = time.isEmpty ? 0 : (outgoing ? 12 : 8)
        self.label.text = text + String(repeating: "\u{00A0}", count: reserve)
        self.label.font = italic ? UIFont.italicSystemFont(ofSize: 15.0) : UIFont.systemFont(ofSize: 16.0)
        self.label.textColor = textColor
        self.bubble.setFill(fill)

        let timeText = NSMutableAttributedString(string: time, attributes: [.foregroundColor: timeColor, .font: UIFont.systemFont(ofSize: 11.0)])
        if !time.isEmpty, let checkColor = checkColor {
            timeText.append(NSAttributedString(string: " ✓", attributes: [.foregroundColor: checkColor, .font: UIFont.systemFont(ofSize: 11.0, weight: .semibold)]))
        }
        self.timeLabel.attributedText = timeText
        self.timeLabel.isHidden = time.isEmpty

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

private func monogramClaudeLoadHistory() -> (messages: [MonogramClaudeMessage], times: [Int32]) {
    guard let data = UserDefaults.standard.data(forKey: monogramClaudeHistoryKey),
          let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
        return ([], [])
    }
    var messages: [MonogramClaudeMessage] = []
    var times: [Int32] = []
    for item in raw {
        guard let role = item["role"], let text = item["text"] else {
            continue
        }
        messages.append(MonogramClaudeMessage(role: role, text: text))
        times.append(Int32(item["time"] ?? "") ?? 0)
    }
    return (messages, times)
}

private func monogramClaudeSaveHistory(_ messages: [MonogramClaudeMessage], times: [Int32]) {
    var raw: [[String: String]] = []
    for (index, message) in messages.enumerated() {
        raw.append(["role": message.role, "text": message.text, "time": String(index < times.count ? times[index] : 0)])
    }
    raw = Array(raw.suffix(monogramClaudeHistoryLimit))
    if let data = try? JSONSerialization.data(withJSONObject: raw) {
        UserDefaults.standard.set(data, forKey: monogramClaudeHistoryKey)
    }
}

private final class MonogramClaudeChatNode: ASDisplayNode, UITableViewDataSource, UITextViewDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData

    private let wallpaperView = UIView()
    private let wallpaperLayer = CAGradientLayer()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputBar = UIView()
    private let fieldBackground = UIView()
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let photoButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)

    private var messages: [MonogramClaudeMessage]
    private var times: [Int32]
    private var isLoading = false
    private var errorText: String?
    private var pendingImage: String?
    private var rows: [MonogramClaudeRow] = []

    private var validLayout: (ContainerViewLayout, CGFloat)?
    private var textHeight: CGFloat = 40.0

    init(context: AccountContext, presentationData: PresentationData) {
        self.context = context
        self.presentationData = presentationData
        let history = monogramClaudeLoadHistory()
        self.messages = history.messages
        self.times = history.times
        super.init()
        self.setViewBlock({
            return UIView()
        })
    }

    override func didLoad() {
        super.didLoad()

        self.wallpaperView.layer.addSublayer(self.wallpaperLayer)
        self.view.addSubview(self.wallpaperView)

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
        self.inputBar.addSubview(self.fieldBackground)

        self.textView.delegate = self
        self.textView.font = UIFont.systemFont(ofSize: 16.0)
        self.textView.backgroundColor = .clear
        self.textView.textContainerInset = UIEdgeInsets(top: 10.0, left: 12.0, bottom: 10.0, right: 8.0)
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
        let panel = theme.chat.inputPanel

        let wallpaperColors = monogramClaudeWallpaperColors(self.presentationData.chatWallpaper, theme: theme)
        self.backgroundColor = wallpaperColors[0]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if wallpaperColors.count > 1 {
            self.wallpaperLayer.colors = wallpaperColors.map { $0.cgColor }
        } else {
            self.wallpaperLayer.colors = [wallpaperColors[0].cgColor, wallpaperColors[0].cgColor]
        }
        self.wallpaperLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.wallpaperLayer.endPoint = CGPoint(x: 0.0, y: 1.0)
        CATransaction.commit()

        self.inputBar.backgroundColor = .clear
        self.fieldBackground.backgroundColor = panel.inputBackgroundColor
        self.fieldBackground.layer.borderWidth = 0.5
        self.fieldBackground.layer.borderColor = panel.inputStrokeColor.cgColor
        self.textView.textColor = panel.inputTextColor
        self.textView.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        self.placeholder.textColor = panel.inputPlaceholderColor
        for button in [self.photoButton, self.sendButton] {
            button.layer.cornerRadius = 20.0
            button.layer.borderWidth = 0.5
            button.layer.borderColor = panel.inputStrokeColor.cgColor
        }
        self.updateControls()
    }

    private func updateControls() {
        let theme = self.presentationData.theme
        let panel = theme.chat.inputPanel
        let hasText = !self.textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.placeholder.isHidden = !self.textView.text.isEmpty
        let canSend = (hasText || self.pendingImage != nil) && !self.isLoading
        self.sendButton.isEnabled = canSend
        let sendConfig = UIImage.SymbolConfiguration(pointSize: 18.0, weight: .bold)
        self.sendButton.setImage(UIImage(systemName: "arrow.up", withConfiguration: sendConfig), for: .normal)
        self.sendButton.backgroundColor = canSend ? theme.list.itemAccentColor : panel.inputBackgroundColor
        self.sendButton.tintColor = canSend ? UIColor.white : panel.panelControlColor.withAlphaComponent(0.5)

        let photoConfig = UIImage.SymbolConfiguration(pointSize: 19.0, weight: .regular)
        self.photoButton.setImage(UIImage(systemName: "paperclip", withConfiguration: photoConfig), for: .normal)
        self.photoButton.backgroundColor = self.pendingImage == nil ? panel.inputBackgroundColor : theme.list.itemAccentColor
        self.photoButton.tintColor = self.pendingImage == nil ? panel.panelControlColor : UIColor.white
    }

    private func reloadRows(scroll: Bool) {
        var rows: [MonogramClaudeRow] = []
        for (index, message) in self.messages.enumerated() {
            rows.append(.message(message, index < self.times.count ? self.times[index] : 0))
        }
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
        let fieldLeft = left + 8.0 + buttonSize + 6.0
        let fieldWidth = max(60.0, size.width - fieldLeft - right - 8.0 - buttonSize - 6.0)
        let fitting = self.textView.sizeThatFits(CGSize(width: fieldWidth, height: CGFloat.greatestFiniteMagnitude)).height
        self.textHeight = min(120.0, max(40.0, fitting))

        let barHeight = self.textHeight + 12.0
        let barFrame = CGRect(x: 0.0, y: size.height - bottomInset - barHeight, width: size.width, height: barHeight + bottomInset)

        self.wallpaperView.frame = CGRect(origin: .zero, size: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.wallpaperLayer.frame = CGRect(origin: .zero, size: size)
        CATransaction.commit()

        transition.updateFrame(view: self.inputBar, frame: barFrame)
        self.fieldBackground.frame = CGRect(x: fieldLeft, y: 6.0, width: fieldWidth, height: self.textHeight)
        self.fieldBackground.layer.cornerRadius = min(20.0, self.textHeight / 2.0)
        self.textView.frame = CGRect(origin: .zero, size: CGSize(width: fieldWidth, height: self.textHeight))
        self.placeholder.sizeToFit()
        self.placeholder.frame = CGRect(x: 16.0, y: floor((self.textHeight - self.placeholder.bounds.height) / 2.0), width: self.placeholder.bounds.width, height: self.placeholder.bounds.height)
        let buttonY = 6.0 + self.textHeight - buttonSize
        self.photoButton.frame = CGRect(x: left + 8.0, y: buttonY, width: buttonSize, height: buttonSize)
        self.sendButton.frame = CGRect(x: size.width - right - 8.0 - buttonSize, y: buttonY, width: buttonSize, height: buttonSize)

        transition.updateFrame(view: self.tableView, frame: CGRect(origin: .zero, size: size))
        self.tableView.contentInset = UIEdgeInsets(top: navigationBarHeight + 4.0, left: 0.0, bottom: size.height - barFrame.minY + 6.0, right: 0.0)
        self.tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: navigationBarHeight, left: 0.0, bottom: size.height - barFrame.minY, right: 0.0)

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
        let chat = theme.chat.message
        let incomingFill = chat.incoming.bubble.withWallpaper.fill
        switch self.rows[indexPath.row] {
        case let .message(message, time):
            let outgoing = message.role == "user"
            let part = outgoing ? chat.outgoing : chat.incoming
            let text = (message.imageBase64 != nil ? "📷 " : "") + message.text
            cell.configure(text: text, time: monogramClaudeTimeText(time), outgoing: outgoing, italic: false, fill: part.bubble.withWallpaper.fill, textColor: part.primaryTextColor, timeColor: part.secondaryTextColor, checkColor: outgoing ? chat.outgoingCheckColor : nil)
        case .typing:
            cell.configure(text: "Claude печатает…", time: "", outgoing: false, italic: true, fill: incomingFill, textColor: chat.incoming.secondaryTextColor, timeColor: chat.incoming.secondaryTextColor, checkColor: nil)
        case let .error(text):
            cell.configure(text: "Ошибка: \(text)", time: "", outgoing: false, italic: true, fill: incomingFill, textColor: theme.list.itemDestructiveColor, timeColor: chat.incoming.secondaryTextColor, checkColor: nil)
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
        self.times.append(Int32(Date().timeIntervalSince1970))
        self.textView.text = ""
        self.pendingImage = nil
        self.isLoading = true
        self.reloadRows(scroll: true)
        self.updateControls()
        self.relayout()
        monogramClaudeSaveHistory(self.messages, times: self.times)

        monogramClaudeSend(apiKey: settings.claudeApiKey, model: settings.claudeModel, effort: settings.claudeEffort, messages: self.messages, completion: { [weak self] result in
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                self.isLoading = false
                switch result {
                case let .success(answer):
                    self.messages.append(MonogramClaudeMessage(role: "assistant", text: answer))
                    self.times.append(Int32(Date().timeIntervalSince1970))
                    settings.claudeLastPreview = String(answer.prefix(200)).replacingOccurrences(of: "\n", with: " ")
                    settings.claudeLastTimestamp = Int32(Date().timeIntervalSince1970)
                    monogramClaudeSaveHistory(self.messages, times: self.times)
                case let .failure(error):
                    if self.messages.last?.role == "user" {
                        let failed = self.messages.removeLast()
                        if !self.times.isEmpty {
                            self.times.removeLast()
                        }
                        self.textView.text = failed.text
                        self.pendingImage = failed.imageBase64
                    }
                    self.errorText = error.text
                    monogramClaudeSaveHistory(self.messages, times: self.times)
                }
                self.reloadRows(scroll: true)
                self.updateControls()
                self.relayout()
            }
        })
    }

    func clearHistory() {
        self.messages = []
        self.times = []
        self.errorText = nil
        monogramClaudeSaveHistory([], times: [])
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
