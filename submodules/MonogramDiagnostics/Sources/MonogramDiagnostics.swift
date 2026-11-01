import Foundation
import UIKit
import MetricKit
import MachO
import os

/// Журнал диагностики (нагрев, нагрузка, действия, ошибки, зависания). Выключен по умолчанию.
/// Пишет в Documents/Logs (видно в «Файлы → На iPhone → Monogram») и копирует в папку архива, если она выбрана.
public final class MonogramDiagnostics: NSObject {
    public static let shared = MonogramDiagnostics()

    private static let enabledKey = "monogram_diagnosticsEnabled"
    private static let bookmarkKey = "monogram_archiveBookmark"
    private static let keepDays = 7
    private static let sampleInterval: TimeInterval = 10.0
    private static let hangThreshold: TimeInterval = 2.0
    private static let hotCpuThreshold: Double = 80.0

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
    private var externalPending = ""
    private var externalPendingName = ""
    private var externalFlushScheduled = false
    private static let urgentCategories: Set<String> = ["app", "hang", "memory", "thermal", "power", "crash", "diag"]

    private var externalBookmark: Data?
    private var externalRoot: URL?
    private var currentDay = ""
    private var previousExceptionHandler: (@convention(c) (NSException) -> Void)?
    private var mainMachThread: mach_port_t = 0
    private var lastFootprintBytes: UInt64 = 0
    private var lastFootprintTime: TimeInterval = 0.0
    private var imageTableLogged = false

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

        self.mainMachThread = pthread_mach_thread_np(pthread_self())
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

        let processInfo = ProcessInfo.processInfo
        self.log("diag", "процесс \(processInfo.processIdentifier); аргументы запуска: \(processInfo.arguments.dropFirst().joined(separator: " ")); физическая память \(processInfo.physicalMemory / 1048576) МБ; локаль \(Locale.current.identifier)")
        self.queue.async {
            self.logImageTable()
        }

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
            self.log("memory", "предупреждение о нехватке памяти; \(self.memoryFootprintText())")
            self.queue.async {
                self.logHotThreads(reason: "предупреждение о памяти", cpuThreshold: 0.0)
            }
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
        watchdog.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(500))
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
                if self.mainMachThread != 0 {
                    let frames = self.backtrace(of: self.mainMachThread, depth: 40)
                    self.write(date: Date(), category: "hang", message: "стек главного потока: \(self.describe(frames: frames))")
                }
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
        let text = "cpu \(String(format: "%.0f", usage.percent))%; потоков \(usage.threads); память \(self.memoryFootprintText()); нагрев \(thermal)"
        self.write(date: Date(), category: "load", message: text)

        if usage.percent >= MonogramDiagnostics.hotCpuThreshold {
            for attempt in 0 ..< 3 {
                if attempt > 0 {
                    Thread.sleep(forTimeInterval: 0.25)
                }
                self.logHotThreads(reason: "cpu \(String(format: "%.0f", usage.percent))%, снимок \(attempt + 1)/3", cpuThreshold: 15.0)
            }
        }

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
        let now = ProcessInfo.processInfo.systemUptime
        var growth = ""
        if self.lastFootprintTime > 0.0 && now > self.lastFootprintTime {
            let delta = (Double(info.phys_footprint) - Double(self.lastFootprintBytes)) / 1048576.0 / (now - self.lastFootprintTime)
            growth = String(format: "; рост %+.1f МБ/с", delta)
        }
        self.lastFootprintBytes = info.phys_footprint
        self.lastFootprintTime = now
        let available = os_proc_available_memory() / 1048576
        return "\(Int(Double(info.phys_footprint) / 1048576.0)) МБ (до лимита \(available) МБ)\(growth)"
    }

    // MARK: - Потоки и стеки

    private struct ThreadSnapshot {
        let port: thread_act_t
        let cpu: Double
        let name: String
    }

    private func threadSnapshots() -> [ThreadSnapshot] {
        var threadList: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threadList, &count) == KERN_SUCCESS, let list = threadList else {
            return []
        }
        let own = pthread_mach_thread_np(pthread_self())
        var result: [ThreadSnapshot] = []
        for index in 0 ..< Int(count) {
            let port = list[index]
            if port == own {
                continue
            }
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let status = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { rebound in
                    thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), rebound, &infoCount)
                }
            }
            if status != KERN_SUCCESS || (info.flags & TH_FLAGS_IDLE) != 0 {
                continue
            }
            var name = ""
            let pthreadHandle: pthread_t? = pthread_from_mach_thread_np(port)
            if let pthread = pthreadHandle {
                var buffer = [CChar](repeating: 0, count: 64)
                if pthread_getname_np(pthread, &buffer, buffer.count) == 0 {
                    name = String(cString: buffer)
                }
            }
            if port == self.mainMachThread {
                name = "main"
            }
            result.append(ThreadSnapshot(port: port, cpu: Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0, name: name))
        }
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        return result
    }

    private func logHotThreads(reason: String, cpuThreshold: Double) {
        let snapshots = self.threadSnapshots().sorted { $0.cpu > $1.cpu }
        let hot = snapshots.filter { $0.cpu >= cpuThreshold }.prefix(4)
        if hot.isEmpty {
            self.write(date: Date(), category: "hot", message: "\(reason): потоков с заметной нагрузкой нет")
        }
        for snapshot in hot {
            let frames = self.backtrace(of: snapshot.port, depth: 48)
            self.write(date: Date(), category: "hot", message: "\(reason); поток «\(snapshot.name)» #\(snapshot.port) cpu \(String(format: "%.0f", snapshot.cpu))%: \(self.describe(frames: frames))")
        }
    }

    /// Стек чужого потока по цепочке frame pointer. Пока поток остановлен, память не выделяется.
    private func backtrace(of thread: thread_act_t, depth: Int) -> [UInt] {
        #if arch(arm64)
        var frames = [UInt]()
        frames.reserveCapacity(depth + 4)
        var state = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        if thread_suspend(thread) != KERN_SUCCESS {
            return frames
        }
        let status = withUnsafeMutablePointer(to: &state) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) { rebound in
                thread_get_state(thread, thread_state_flavor_t(ARM_THREAD_STATE64), rebound, &stateCount)
            }
        }
        if status == KERN_SUCCESS {
            let mask: UInt = 0x0000_007F_FFFF_FFFF
            frames.append(UInt(state.__pc) & mask)
            frames.append(UInt(state.__lr) & mask)
            var fp = UInt(state.__fp) & mask
            var pair: (UInt, UInt) = (0, 0)
            var level = 0
            while level < depth && fp != 0 && (fp & 0x7) == 0 {
                var readSize: vm_size_t = 0
                let readStatus = withUnsafeMutablePointer(to: &pair) { pointer -> kern_return_t in
                    vm_read_overwrite(mach_task_self_, vm_address_t(fp), vm_size_t(16), vm_address_t(UInt(bitPattern: pointer)), &readSize)
                }
                if readStatus != KERN_SUCCESS || readSize != 16 {
                    break
                }
                let next = pair.0 & mask
                let returnAddress = pair.1 & mask
                if returnAddress == 0 {
                    break
                }
                frames.append(returnAddress)
                if next <= fp {
                    break
                }
                fp = next
                level += 1
            }
        }
        thread_resume(thread)
        return frames
        #else
        return []
        #endif
    }

    private struct LoadedImage {
        let name: String
        let base: UInt
        let uuid: String
    }

    private func loadedImages() -> [LoadedImage] {
        var result: [LoadedImage] = []
        let total = _dyld_image_count()
        for index in 0 ..< total {
            guard let header = _dyld_get_image_header(index), let cName = _dyld_get_image_name(index) else {
                continue
            }
            let path = String(cString: cName)
            result.append(LoadedImage(name: (path as NSString).lastPathComponent, base: UInt(bitPattern: header), uuid: self.imageUUID(header)))
        }
        return result
    }

    private func imageUUID(_ header: UnsafePointer<mach_header>) -> String {
        let raw = UnsafeRawPointer(header)
        let commandCount = raw.load(fromByteOffset: 16, as: UInt32.self)
        var offset = 32
        for _ in 0 ..< commandCount {
            let command = raw.load(fromByteOffset: offset, as: UInt32.self)
            let size = raw.load(fromByteOffset: offset + 4, as: UInt32.self)
            if command == UInt32(LC_UUID) {
                var text = ""
                for byte in 0 ..< 16 {
                    text += String(format: "%02X", raw.load(fromByteOffset: offset + 8 + byte, as: UInt8.self))
                }
                return text
            }
            if size == 0 {
                break
            }
            offset += Int(size)
        }
        return "?"
    }

    private func logImageTable() {
        if self.imageTableLogged {
            return
        }
        self.imageTableLogged = true
        for image in self.loadedImages() where image.name.hasSuffix("Framework") || image.name == "Telegram" {
            self.write(date: Date(), category: "image", message: "\(image.name) база 0x\(String(image.base, radix: 16)) uuid \(image.uuid)")
        }
    }

    private func describe(frames: [UInt]) -> String {
        if frames.isEmpty {
            return "(стек недоступен)"
        }
        let images = self.loadedImages().sorted { $0.base < $1.base }
        var parts: [String] = []
        for address in frames {
            var match: LoadedImage?
            for image in images where image.base <= address {
                match = image
            }
            if let match {
                parts.append("\(match.name)+0x\(String(address - match.base, radix: 16))")
            } else {
                parts.append("0x\(String(address, radix: 16))")
            }
        }
        return parts.joined(separator: " < ")
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
        // Копия в iCloud Drive пишется пачками: каждая запись туда будит системную синхронизацию.
        if self.externalPendingName != name {
            self.flushExternal()
            self.externalPendingName = name
        }
        self.externalPending += line
        if MonogramDiagnostics.urgentCategories.contains(category) || self.externalPending.utf8.count > 16384 {
            self.flushExternal()
        } else if !self.externalFlushScheduled {
            self.externalFlushScheduled = true
            self.queue.asyncAfter(deadline: .now() + 30.0) { [weak self] in
                guard let self else {
                    return
                }
                self.externalFlushScheduled = false
                self.flushExternal()
            }
        }
    }

    private func flushExternal() {
        if self.externalPending.isEmpty {
            return
        }
        let text = self.externalPending
        self.externalPending = ""
        if let external = self.externalLogsDirectory() {
            self.append(text, to: external.appendingPathComponent(self.externalPendingName))
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
