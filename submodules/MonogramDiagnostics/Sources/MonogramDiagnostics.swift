import Foundation
import UIKit
import MetricKit

/// Журнал диагностики (нагрев, нагрузка, действия, ошибки, зависания). Выключен по умолчанию.
/// Пишет в Documents/Logs (видно в «Файлы → На iPhone → Monogram») и копирует в папку архива, если она выбрана.
public final class MonogramDiagnostics: NSObject {
    public static let shared = MonogramDiagnostics()

    private static let enabledKey = "monogram_diagnosticsEnabled"
    private static let bookmarkKey = "monogram_archiveBookmark"
    private static let keepDays = 7
    private static let sampleInterval: TimeInterval = 10.0
    private static let hangThreshold: TimeInterval = 2.0

    private let queue = DispatchQueue(label: "monogram.diagnostics", qos: .utility)
    private let stateLock = NSLock()

    private var enabledValue: Bool
    private var started = false
    private var isActive = true
    private var lastPong: TimeInterval = 0.0
    private var hangReported = false
    private var observers: [NSObjectProtocol] = []
    private var sampleTimer: DispatchSourceTimer?
    private var watchdogTimer: DispatchSourceTimer?

    private var externalBookmark: Data?
    private var externalRoot: URL?
    private var currentDay = ""
    private var previousExceptionHandler: (@convention(c) (NSException) -> Void)?

    private let lineFormatter: DateFormatter
    private let dayFormatter: DateFormatter

    private override init() {
        self.enabledValue = UserDefaults.standard.bool(forKey: MonogramDiagnostics.enabledKey)
        self.lineFormatter = DateFormatter()
        self.lineFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.lineFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.dayFormatter = DateFormatter()
        self.dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dayFormatter.dateFormat = "yyyy-MM-dd"
        super.init()
    }

    public var isEnabled: Bool {
        get {
            self.stateLock.lock()
            defer { self.stateLock.unlock() }
            return self.enabledValue
        }
        set {
            self.stateLock.lock()
            let changed = self.enabledValue != newValue
            self.enabledValue = newValue
            self.stateLock.unlock()
            UserDefaults.standard.set(newValue, forKey: MonogramDiagnostics.enabledKey)
            if changed {
                if newValue {
                    self.start()
                } else {
                    let date = Date()
                    self.queue.async {
                        self.write(date: date, category: "diag", message: "журнал выключен")
                    }
                    self.stop()
                }
            }
        }
    }

    /// Вызывается при запуске приложения: ничего не делает, пока журнал выключен.
    public func start() {
        if !self.isEnabled {
            return
        }
        DispatchQueue.main.async {
            self.startOnMain()
        }
    }

    public func log(_ category: String, _ message: String) {
        if !self.isEnabled {
            return
        }
        let date = Date()
        self.queue.async {
            self.write(date: date, category: category, message: message)
        }
    }

    // MARK: - Запуск и остановка

    private func startOnMain() {
        self.stateLock.lock()
        if self.started {
            self.stateLock.unlock()
            return
        }
        self.started = true
        self.stateLock.unlock()

        UIDevice.current.isBatteryMonitoringEnabled = true
        self.isActive = UIApplication.shared.applicationState == .active
        self.stateLock.lock()
        self.lastPong = ProcessInfo.processInfo.systemUptime
        self.stateLock.unlock()

        let device = UIDevice.current
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
        self.log("diag", "журнал включён; версия \(version); iOS \(device.systemVersion); модель \(self.machineName()); ядер \(ProcessInfo.processInfo.activeProcessorCount)")
        self.log("thermal", "состояние: \(self.thermalName(ProcessInfo.processInfo.thermalState)); энергосбережение: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "вкл" : "выкл")")

        self.installObservers()
        self.installExceptionHandler()
        MXMetricManager.shared.add(self)

        self.queue.async {
            self.cleanupOldLogs()
            self.startTimers()
        }
    }

    private func stop() {
        self.stateLock.lock()
        let wasStarted = self.started
        self.started = false
        self.stateLock.unlock()
        if !wasStarted {
            return
        }
        DispatchQueue.main.async {
            for observer in self.observers {
                NotificationCenter.default.removeObserver(observer)
            }
            self.observers = []
            MXMetricManager.shared.remove(self)
        }
        self.queue.async {
            self.sampleTimer?.cancel()
            self.sampleTimer = nil
            self.watchdogTimer?.cancel()
            self.watchdogTimer = nil
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        func add(_ name: Notification.Name, _ handler: @escaping (Notification) -> Void) {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: nil, using: handler))
        }
        add(ProcessInfo.thermalStateDidChangeNotification) { [weak self] _ in
            guard let self else { return }
            self.log("thermal", "состояние изменилось: \(self.thermalName(ProcessInfo.processInfo.thermalState))")
        }
        add(.NSProcessInfoPowerStateDidChange) { [weak self] _ in
            self?.log("power", "энергосбережение: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "вкл" : "выкл")")
        }
        add(UIApplication.didBecomeActiveNotification) { [weak self] _ in
            guard let self else { return }
            self.stateLock.lock()
            self.isActive = true
            self.lastPong = ProcessInfo.processInfo.systemUptime
            self.hangReported = false
            self.stateLock.unlock()
            self.log("app", "приложение активно")
        }
        add(UIApplication.willResignActiveNotification) { [weak self] _ in
            guard let self else { return }
            self.stateLock.lock()
            self.isActive = false
            self.stateLock.unlock()
            self.log("app", "приложение стало неактивным")
        }
        add(UIApplication.didEnterBackgroundNotification) { [weak self] _ in
            self?.log("app", "ушло в фон")
        }
        add(UIApplication.willEnterForegroundNotification) { [weak self] _ in
            self?.log("app", "возвращается на передний план")
        }
        add(UIApplication.didReceiveMemoryWarningNotification) { [weak self] _ in
            guard let self else { return }
            self.log("memory", "предупреждение о нехватке памяти; занято \(self.memoryFootprintText())")
        }
        add(UIApplication.willTerminateNotification) { [weak self] _ in
            self?.log("app", "приложение завершается")
        }
    }

    private func installExceptionHandler() {
        self.previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            let diagnostics = MonogramDiagnostics.shared
            let text = "необработанное исключение \(exception.name.rawValue): \(exception.reason ?? "")\n" + exception.callStackSymbols.joined(separator: "\n")
            diagnostics.queue.sync {
                diagnostics.write(date: Date(), category: "crash", message: text)
            }
            diagnostics.previousExceptionHandler?(exception)
        }
    }

    // MARK: - Таймеры

    private func startTimers() {
        let sampler = DispatchSource.makeTimerSource(queue: self.queue)
        sampler.schedule(deadline: .now() + 2.0, repeating: MonogramDiagnostics.sampleInterval, leeway: .seconds(1))
        sampler.setEventHandler { [weak self] in
            self?.takeSample()
        }
        sampler.resume()
        self.sampleTimer = sampler

        let watchdog = DispatchSource.makeTimerSource(queue: self.queue)
        watchdog.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(200))
        watchdog.setEventHandler { [weak self] in
            self?.watchdogTick()
        }
        watchdog.resume()
        self.watchdogTimer = watchdog
    }

    private func watchdogTick() {
        let now = ProcessInfo.processInfo.systemUptime
        self.stateLock.lock()
        let active = self.isActive
        let last = self.lastPong
        let reported = self.hangReported
        self.stateLock.unlock()

        if active {
            let blocked = now - last
            if blocked > MonogramDiagnostics.hangThreshold && !reported {
                self.stateLock.lock()
                self.hangReported = true
                self.stateLock.unlock()
                self.write(date: Date(), category: "hang", message: "главный поток не отвечает уже \(String(format: "%.1f", blocked)) с")
            }
        }

        DispatchQueue.main.async {
            self.stateLock.lock()
            let wasReported = self.hangReported
            let previous = self.lastPong
            self.lastPong = ProcessInfo.processInfo.systemUptime
            self.hangReported = false
            self.stateLock.unlock()
            if wasReported {
                let total = ProcessInfo.processInfo.systemUptime - previous
                self.log("hang", "главный поток снова отвечает; блокировка длилась около \(String(format: "%.1f", total)) с")
            }
        }
    }

    private func takeSample() {
        let usage = self.cpuUsage()
        let thermal = self.thermalName(ProcessInfo.processInfo.thermalState)
        let memory = self.memoryFootprintText()
        let text = "cpu \(String(format: "%.0f", usage.percent))%; потоков \(usage.threads); память \(memory); нагрев \(thermal)"
        self.write(date: Date(), category: "load", message: text)

        DispatchQueue.main.async {
            let device = UIDevice.current
            let level = device.batteryLevel
            if level >= 0 {
                self.log("battery", "заряд \(Int(level * 100))%; \(self.batteryStateName(device.batteryState))")
            }
        }
    }

    // MARK: - Замеры

    private func cpuUsage() -> (percent: Double, threads: Int) {
        var threadList: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threadList, &count) == KERN_SUCCESS, let list = threadList else {
            return (0.0, 0)
        }
        var total = 0.0
        for index in 0 ..< Int(count) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { rebound in
                    thread_info(list[index], thread_flavor_t(THREAD_BASIC_INFO), rebound, &infoCount)
                }
            }
            if result == KERN_SUCCESS && (info.flags & TH_FLAGS_IDLE) == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        return (total, Int(count))
    }

    private func memoryFootprintText() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        if result != KERN_SUCCESS {
            return "?"
        }
        return "\(Int(Double(info.phys_footprint) / 1048576.0)) МБ"
    }

    private func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal (норма)"
        case .fair:
            return "fair (тепло)"
        case .serious:
            return "SERIOUS (горячо, система снижает частоты)"
        case .critical:
            return "CRITICAL (критично)"
        @unknown default:
            return "unknown"
        }
    }

    private func batteryStateName(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging:
            return "заряжается"
        case .full:
            return "заряжен"
        case .unplugged:
            return "от батареи"
        default:
            return "неизвестно"
        }
    }

    private func machineName() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    // MARK: - Файлы

    private func localLogsDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }

    private func externalLogsDirectory() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: MonogramDiagnostics.bookmarkKey) else {
            self.externalBookmark = nil
            self.externalRoot = nil
            return nil
        }
        if self.externalBookmark != data || self.externalRoot == nil {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
                return nil
            }
            _ = url.startAccessingSecurityScopedResource()
            self.externalBookmark = data
            self.externalRoot = url
        }
        guard let root = self.externalRoot else {
            return nil
        }
        let directory = root.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }

    private func write(date: Date, category: String, message: String) {
        let day = self.dayFormatter.string(from: date)
        if day != self.currentDay {
            self.currentDay = day
            self.cleanupOldLogs()
        }
        let line = "[\(self.lineFormatter.string(from: date))] [\(category)] \(message)\n"
        let name = "monogram-\(day).log"
        self.append(line, to: self.localLogsDirectory().appendingPathComponent(name))
        if let external = self.externalLogsDirectory() {
            self.append(line, to: external.appendingPathComponent(name))
        }
    }

    private func writeRaw(name: String, data: Data) {
        let stamp = self.dayFormatter.string(from: Date())
        let fileName = "monogram-\(name)-\(stamp)-\(Int(Date().timeIntervalSince1970)).json"
        try? data.write(to: self.localLogsDirectory().appendingPathComponent(fileName), options: .atomic)
        if let external = self.externalLogsDirectory() {
            try? data.write(to: external.appendingPathComponent(fileName), options: .atomic)
        }
    }

    private func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else {
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func cleanupOldLogs() {
        let threshold = Date().addingTimeInterval(-Double(MonogramDiagnostics.keepDays) * 86400.0)
        var directories = [self.localLogsDirectory()]
        if let external = self.externalLogsDirectory() {
            directories.append(external)
        }
        for directory in directories {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for url in urls where url.lastPathComponent.hasPrefix("monogram-") {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified < threshold {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }
}

extension MonogramDiagnostics: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            self.queue.async {
                self.writeRaw(name: "metrics", data: data)
            }
        }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            self.queue.async {
                self.writeRaw(name: "diagnostics", data: data)
            }
        }
    }
}
