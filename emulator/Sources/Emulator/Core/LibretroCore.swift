import Foundation
import AppKit
import CLibretro

enum EmulatorError: LocalizedError {
    case coreLoadFailed(String)
    case symbolNotFound(String)
    case gameLoadFailed
    case noCore

    var errorDescription: String? {
        switch self {
        case .coreLoadFailed(let msg): return "コアの読み込みに失敗: \(msg)"
        case .symbolNotFound(let sym): return "シンボルが見つかりません: \(sym)"
        case .gameLoadFailed: return "ROMの読み込みに失敗しました"
        case .noCore: return "コアが見つかりません"
        }
    }
}

final class LibretroCore: ObservableObject {
    static var current: LibretroCore?

    @Published var currentFrame: CGImage?
    @Published var isRunning = false
    @Published var isPaused = false

    private var handle: UnsafeMutableRawPointer?
    private var romData: Data?
    /// 実行中の ROM 名(拡張子なし)。SRAM・ステートの保存ファイル名に使う
    private var currentGameName: String?
    private var runTimer: DispatchSourceTimer?
    private let emulationQueue = DispatchQueue(label: "com.retrogames.emulation", qos: .userInteractive)

    var pixelFormat: Int32 = RETRO_PIXEL_FORMAT_0RGB1555
    var systemDirectory: String
    var saveDirectory: String
    var avInfo = retro_system_av_info()

    var audioEngine: AudioEngine?
    var inputManager: InputManager?

    // Function pointers
    private var fn_retro_init: (@convention(c) () -> Void)?
    private var fn_retro_deinit: (@convention(c) () -> Void)?
    private var fn_retro_run: (@convention(c) () -> Void)?
    private var fn_retro_load_game: (@convention(c) (UnsafePointer<retro_game_info>?) -> Bool)?
    private var fn_retro_unload_game: (@convention(c) () -> Void)?
    private var fn_retro_set_environment: (@convention(c) (retro_environment_t?) -> Void)?
    private var fn_retro_set_video_refresh: (@convention(c) (retro_video_refresh_t?) -> Void)?
    private var fn_retro_set_audio_sample: (@convention(c) (retro_audio_sample_t?) -> Void)?
    private var fn_retro_set_audio_sample_batch: (@convention(c) (retro_audio_sample_batch_t?) -> Void)?
    private var fn_retro_set_input_poll: (@convention(c) (retro_input_poll_t?) -> Void)?
    private var fn_retro_set_input_state: (@convention(c) (retro_input_state_t?) -> Void)?
    private var fn_retro_get_system_info: (@convention(c) (UnsafeMutablePointer<retro_system_info>?) -> Void)?
    private var fn_retro_get_system_av_info: (@convention(c) (UnsafeMutablePointer<retro_system_av_info>?) -> Void)?
    private var fn_retro_set_controller_port_device: (@convention(c) (UInt32, UInt32) -> Void)?
    private var fn_retro_reset: (@convention(c) () -> Void)?
    private var fn_retro_serialize_size: (@convention(c) () -> Int)?
    private var fn_retro_serialize: (@convention(c) (UnsafeMutableRawPointer?, Int) -> Bool)?
    private var fn_retro_unserialize: (@convention(c) (UnsafeRawPointer?, Int) -> Bool)?
    private var fn_retro_get_memory_data: (@convention(c) (UInt32) -> UnsafeMutableRawPointer?)?
    private var fn_retro_get_memory_size: (@convention(c) (UInt32) -> Int)?
    private var fn_retro_api_version: (@convention(c) () -> UInt32)?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("RetroGames")
        systemDirectory = base.appendingPathComponent("System").path
        saveDirectory = base.appendingPathComponent("Saves").path

        for dir in [systemDirectory, saveDirectory,
                    base.appendingPathComponent("Cores").path,
                    base.appendingPathComponent("States").path] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
    }

    func loadCore(at path: String) throws {
        unloadCore()
        LibretroCore.current = self

        guard let h = dlopen(path, RTLD_LAZY) else {
            let err = String(cString: dlerror())
            throw EmulatorError.coreLoadFailed(err)
        }
        handle = h

        func resolve<T>(_ name: String) throws -> T {
            guard let sym = dlsym(h, name) else {
                throw EmulatorError.symbolNotFound(name)
            }
            return unsafeBitCast(sym, to: T.self)
        }

        fn_retro_init = try resolve("retro_init")
        fn_retro_deinit = try resolve("retro_deinit")
        fn_retro_run = try resolve("retro_run")
        fn_retro_load_game = try resolve("retro_load_game")
        fn_retro_unload_game = try resolve("retro_unload_game")
        fn_retro_set_environment = try resolve("retro_set_environment")
        fn_retro_set_video_refresh = try resolve("retro_set_video_refresh")
        fn_retro_set_audio_sample = try resolve("retro_set_audio_sample")
        fn_retro_set_audio_sample_batch = try resolve("retro_set_audio_sample_batch")
        fn_retro_set_input_poll = try resolve("retro_set_input_poll")
        fn_retro_set_input_state = try resolve("retro_set_input_state")
        fn_retro_get_system_info = try resolve("retro_get_system_info")
        fn_retro_get_system_av_info = try resolve("retro_get_system_av_info")
        fn_retro_set_controller_port_device = try resolve("retro_set_controller_port_device")
        fn_retro_reset = try resolve("retro_reset")
        fn_retro_serialize_size = try resolve("retro_serialize_size")
        fn_retro_serialize = try resolve("retro_serialize")
        fn_retro_unserialize = try resolve("retro_unserialize")
        fn_retro_get_memory_data = try resolve("retro_get_memory_data")
        fn_retro_get_memory_size = try resolve("retro_get_memory_size")
        fn_retro_api_version = try resolve("retro_api_version")

        fn_retro_set_environment?(environmentCallback)
        fn_retro_set_video_refresh?(videoRefreshCallback)
        fn_retro_set_audio_sample?(audioSampleCallback)
        fn_retro_set_audio_sample_batch?(audioSampleBatchCallback)
        fn_retro_set_input_poll?(inputPollCallback)
        fn_retro_set_input_state?(inputStateCallback)

        fn_retro_init?()
    }

    func loadGame(at url: URL) throws {
        let data = try Data(contentsOf: url)
        romData = data
        currentGameName = url.deletingPathExtension().lastPathComponent

        let path = url.path
        let success = data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> Bool in
            var gameInfo = retro_game_info(
                path: (path as NSString).utf8String,
                data: rawBuffer.baseAddress,
                size: data.count,
                meta: nil
            )
            return fn_retro_load_game?(&gameInfo) ?? false
        }

        guard success else { throw EmulatorError.gameLoadFailed }

        fn_retro_get_system_av_info?(&avInfo)
        audioEngine?.start(sampleRate: avInfo.timing.sample_rate)
        fn_retro_set_controller_port_device?(0, UInt32(RETRO_DEVICE_JOYPAD))

        startRunLoop()
    }

    func startRunLoop() {
        isRunning = true
        isPaused = false
        let fps = avInfo.timing.fps > 0 ? avInfo.timing.fps : 60.0
        let interval = 1.0 / fps

        let timer = DispatchSource.makeTimerSource(queue: emulationQueue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isPaused else { return }
            self.fn_retro_run?()
        }
        timer.resume()
        runTimer = timer
    }

    func togglePause() {
        isPaused.toggle()
    }

    func reset() {
        emulationQueue.async { [weak self] in
            self?.fn_retro_reset?()
        }
    }

    /// - Parameter completion: emulationQueue 上の後片付け(retro_unload_game)が完了してから
    ///   メインスレッドで呼ばれる。アプリ終了時、実行中の retro_run とプロセス終了処理が
    ///   競合してクラッシュするのを防ぐために使う(applicationShouldTerminate から呼ぶ)。
    func stop(completion: (() -> Void)? = nil) {
        runTimer?.cancel()
        runTimer = nil
        audioEngine?.stop()

        saveSRAM()

        emulationQueue.async { [weak self] in
            self?.fn_retro_unload_game?()
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isPaused = false
                self?.currentFrame = nil
                completion?()
            }
        }
    }

    func unloadCore() {
        if isRunning { stop() }
        emulationQueue.async { [weak self] in
            self?.fn_retro_deinit?()
            if let h = self?.handle {
                dlclose(h)
            }
            self?.handle = nil
        }
        if LibretroCore.current === self {
            LibretroCore.current = nil
        }
    }

    // MARK: - Save States

    /// ステートセーブの保存先。ゲームごとに別ファイルにする
    /// (共有ファイルだと別ゲームのステートを読み込んで壊れるため)
    private func stateFileURL() -> URL? {
        guard let name = currentGameName else { return nil }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("RetroGames/States/\(name).state")
    }

    func saveState() {
        guard let file = stateFileURL() else { return }
        emulationQueue.async { [weak self] in
            guard let self, let size = self.fn_retro_serialize_size?(), size > 0 else { return }
            var buffer = Data(count: size)
            let ok = buffer.withUnsafeMutableBytes { ptr in
                self.fn_retro_serialize?(ptr.baseAddress!, size) ?? false
            }
            guard ok else { return }
            try? buffer.write(to: file)
        }
    }

    func loadState() {
        guard let file = stateFileURL() else { return }
        emulationQueue.async { [weak self] in
            guard let self, let data = try? Data(contentsOf: file) else { return }
            data.withUnsafeBytes { ptr in
                _ = self.fn_retro_unserialize?(ptr.baseAddress!, data.count)
            }
        }
    }

    // MARK: - SRAM

    /// SRAM の保存先もゲームごとに別ファイル。かつては全ゲーム共有の game.srm で、
    /// 別ゲームのセーブを上書きするバグがあった(旧ファイルはもう読み書きしない)
    private func sramFileURL() -> URL? {
        guard let name = currentGameName else { return nil }
        return URL(fileURLWithPath: saveDirectory).appendingPathComponent("\(name).srm")
    }

    private func saveSRAM() {
        guard let file = sramFileURL(),
              let dataPtr = fn_retro_get_memory_data?(UInt32(RETRO_MEMORY_SAVE_RAM)),
              let size = fn_retro_get_memory_size?(UInt32(RETRO_MEMORY_SAVE_RAM)), size > 0 else { return }
        let sramData = Data(bytes: dataPtr, count: size)
        try? sramData.write(to: file)
    }

    func loadSRAM() {
        guard let file = sramFileURL(),
              let data = try? Data(contentsOf: file),
              let dataPtr = fn_retro_get_memory_data?(UInt32(RETRO_MEMORY_SAVE_RAM)),
              let size = fn_retro_get_memory_size?(UInt32(RETRO_MEMORY_SAVE_RAM)), size > 0 else { return }
        _ = data.withUnsafeBytes { ptr in
            memcpy(dataPtr, ptr.baseAddress!, min(data.count, size))
        }
    }

    // MARK: - Frame Buffer → CGImage

    func createImage(data: UnsafeRawPointer, width: UInt32, height: UInt32, pitch: Int) {
        let w = Int(width)
        let h = Int(height)

        var cgImage: CGImage?

        if pixelFormat == RETRO_PIXEL_FORMAT_XRGB8888 {
            let bytesPerRow = pitch
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            if let context = CGContext(data: UnsafeMutableRawPointer(mutating: data),
                                       width: w, height: h,
                                       bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                       space: colorSpace, bitmapInfo: bitmapInfo.rawValue) {
                cgImage = context.makeImage()
            }
        } else if pixelFormat == RETRO_PIXEL_FORMAT_RGB565 {
            let buffer = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
            defer { buffer.deallocate() }

            let src = data.bindMemory(to: UInt16.self, capacity: w * h)
            for y in 0..<h {
                let srcRow = src.advanced(by: y * (pitch / 2))
                let dstRow = buffer.advanced(by: y * w)
                for x in 0..<w {
                    let pixel = srcRow[x]
                    let r = UInt32((pixel >> 11) & 0x1F) * 255 / 31
                    let g = UInt32((pixel >> 5) & 0x3F) * 255 / 63
                    let b = UInt32(pixel & 0x1F) * 255 / 31
                    dstRow[x] = (0xFF << 24) | (r << 16) | (g << 8) | b
                }
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            if let context = CGContext(data: buffer, width: w, height: h,
                                       bitsPerComponent: 8, bytesPerRow: w * 4,
                                       space: colorSpace, bitmapInfo: bitmapInfo.rawValue) {
                cgImage = context.makeImage()
            }
        } else {
            // 0RGB1555 fallback
            let buffer = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
            defer { buffer.deallocate() }

            let src = data.bindMemory(to: UInt16.self, capacity: w * h)
            for y in 0..<h {
                let srcRow = src.advanced(by: y * (pitch / 2))
                let dstRow = buffer.advanced(by: y * w)
                for x in 0..<w {
                    let pixel = srcRow[x]
                    let r = UInt32((pixel >> 10) & 0x1F) * 255 / 31
                    let g = UInt32((pixel >> 5) & 0x1F) * 255 / 31
                    let b = UInt32(pixel & 0x1F) * 255 / 31
                    dstRow[x] = (0xFF << 24) | (r << 16) | (g << 8) | b
                }
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            if let context = CGContext(data: buffer, width: w, height: h,
                                       bitsPerComponent: 8, bytesPerRow: w * 4,
                                       space: colorSpace, bitmapInfo: bitmapInfo.rawValue) {
                cgImage = context.makeImage()
            }
        }

        if let img = cgImage {
            DispatchQueue.main.async { [weak self] in
                self?.currentFrame = img
            }
        }
    }
}

// MARK: - C Callbacks (static, route through LibretroCore.current)

private func environmentCallback(_ cmd: UInt32, _ data: UnsafeMutableRawPointer?) -> Bool {
    guard let core = LibretroCore.current else { return false }

    switch Int32(cmd) {
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
        if let ptr = data?.assumingMemoryBound(to: Int32.self) {
            core.pixelFormat = ptr.pointee
        }
        return true

    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        if let ptr = data?.assumingMemoryBound(to: UnsafePointer<CChar>?.self) {
            ptr.pointee = (core.systemDirectory as NSString).utf8String
        }
        return true

    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        if let ptr = data?.assumingMemoryBound(to: UnsafePointer<CChar>?.self) {
            ptr.pointee = (core.saveDirectory as NSString).utf8String
        }
        return true

    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        data?.assumingMemoryBound(to: Bool.self).pointee = true
        return true

    case RETRO_ENVIRONMENT_GET_VARIABLE:
        return false

    case RETRO_ENVIRONMENT_SET_VARIABLES:
        return true

    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        data?.assumingMemoryBound(to: Bool.self).pointee = false
        return true

    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
        // NULL のままだとコアがログ呼び出しでクラッシュする(nestopia の CPU JAM 等)
        clibretro_fill_log_interface(data)
        return true

    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
        return true

    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
        return true

    case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
        return true

    case RETRO_ENVIRONMENT_GET_OVERSCAN:
        data?.assumingMemoryBound(to: Bool.self).pointee = false
        return true

    case RETRO_ENVIRONMENT_SET_GEOMETRY:
        return true

    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
        return false

    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
        return true

    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
        data?.assumingMemoryBound(to: UInt32.self).pointee = 0
        return true

    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS, RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL,
         RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2, RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:
        return true

    case RETRO_ENVIRONMENT_SET_MESSAGE:
        return true

    case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
        return true

    default:
        return false
    }
}

private let RETRO_ENVIRONMENT_SET_MEMORY_MAPS: Int32 = 36

private func videoRefreshCallback(_ data: UnsafeRawPointer?, _ width: UInt32, _ height: UInt32, _ pitch: Int) {
    guard let core = LibretroCore.current, let data else { return }
    core.createImage(data: data, width: width, height: height, pitch: pitch)
}

private func audioSampleCallback(_ left: Int16, _ right: Int16) {
    guard let core = LibretroCore.current, let engine = core.audioEngine else { return }
    engine.writeSample(left: left, right: right)
}

private func audioSampleBatchCallback(_ data: UnsafePointer<Int16>?, _ frames: Int) -> Int {
    guard let core = LibretroCore.current, let engine = core.audioEngine, let data else { return 0 }
    engine.writeBatch(data: data, frames: frames)
    return frames
}

private func inputPollCallback() {
    // Input state is polled continuously via NSEvent monitors; nothing to do here
}

private func inputStateCallback(_ port: UInt32, _ device: UInt32, _ index: UInt32, _ id: UInt32) -> Int16 {
    guard let core = LibretroCore.current, let input = core.inputManager, port == 0 else { return 0 }
    // RETRO_ENVIRONMENT_GET_INPUT_BITMASKS を true と返しているため、コアはボタン個別
    // 問い合わせの代わりにこの一括ビットマスク問い合わせ(id=256)を使うことがある。
    // 未対応のままだと A/B/X/Y/L/R 等がまとめて反応しなくなる。
    if id == RETRO_DEVICE_ID_JOYPAD_MASK {
        var mask: UInt16 = 0
        for button in UInt32(0)...15 where input.isPressed(button: button) {
            mask |= (1 << button)
        }
        return Int16(bitPattern: mask)
    }
    return input.isPressed(button: id) ? 1 : 0
}

private let RETRO_DEVICE_ID_JOYPAD_MASK: UInt32 = 256
