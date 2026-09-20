import Darwin
import Foundation

final class AppHangWatchdog: @unchecked Sendable {
    static let shared = AppHangWatchdog()

    private let queue = DispatchQueue(label: "livecaption.hang-watchdog", qos: .utility)
    private let lock = NSLock()
    private var lastHeartbeat = DispatchTime.now().uptimeNanoseconds
    private var timer: DispatchSourceTimer?
    private let timeoutNanoseconds: UInt64 = 60 * 1_000_000_000

    private init() {}

    func start() {
        lock.lock()
        guard timer == nil else {
            lock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        lock.unlock()

        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            self.lock.lock()
            let elapsed = now &- self.lastHeartbeat
            self.lock.unlock()
            if elapsed > self.timeoutNanoseconds {
                // Never kill a recording to recover a stalled interface.
                NSLog("LiveCaption: main thread unresponsive for over 60 seconds")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.lastHeartbeat = DispatchTime.now().uptimeNanoseconds
                self.lock.unlock()
            }
        }
        timer.resume()
    }
}
