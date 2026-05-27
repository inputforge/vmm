import Foundation
import Virtualization

final class VMRunner: NSObject, VZVirtualMachineDelegate {
    private let vm: VZVirtualMachine
    private let stopped = DispatchSemaphore(value: 0)
    private var exitError: Error?
    private var sigtermSource: DispatchSourceSignal?
    private var forceStopTimer: DispatchSourceTimer?
    private var terminationRequested = false
    private var gracefulStopStarted = false

    init(configuration: VZVirtualMachineConfiguration) {
        self.vm = VZVirtualMachine(configuration: configuration, queue: .main)
        super.init()
        self.vm.delegate = self
    }

    func run() throws {
        guard VZVirtualMachine.isSupported else {
            throw VMRunnerError.unsupportedHost
        }

        installSignalHandlers()

        vm.start { [weak self] result in
            switch result {
            case .success:
                if self?.terminationRequested == true {
                    self?.requestGracefulStopIfPossible()
                }
            case .failure(let error):
                self?.exitError = error
                self?.stopped.signal()
            }
        }

        while stopped.wait(timeout: .now() + 0.1) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if let exitError {
            throw exitError
        }
    }

    private func installSignalHandlers() {
        signal(SIGTERM, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.terminationRequested = true
            self?.requestGracefulStopIfPossible()
        }
        source.resume()
        sigtermSource = source
    }

    private func requestGracefulStopIfPossible() {
        guard !gracefulStopStarted else {
            return
        }

        if vm.state == .starting {
            return
        }
        if vm.state == .stopped {
            stopped.signal()
            return
        }

        gracefulStopStarted = true

        do {
            try vm.requestStop()
        } catch {
            fputs("warning: failed to request VM stop: \(error)\n", stderr)
            forceStop()
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30)
        timer.setEventHandler { [weak self] in
            self?.forceStop()
        }
        timer.resume()
        forceStopTimer = timer
    }

    private func forceStop() {
        if vm.state == .starting {
            gracefulStopStarted = false
            requestGracefulStopIfPossible()
            return
        }
        guard vm.state != .stopped else {
            return
        }

        vm.stop { [weak self] error in
            if let error {
                self?.exitError = error
            }
            self?.stopped.signal()
        }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        forceStopTimer?.cancel()
        forceStopTimer = nil
        stopped.signal()
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        forceStopTimer?.cancel()
        forceStopTimer = nil
        exitError = error
        stopped.signal()
    }

    func virtualMachine(
        _ virtualMachine: VZVirtualMachine,
        networkDevice: VZNetworkDevice,
        attachmentWasDisconnectedWithError error: Error
    ) {
        fputs("warning: network attachment disconnected: \(error)\n", stderr)
    }
}

enum VMRunnerError: LocalizedError {
    case unsupportedHost

    var errorDescription: String? {
        switch self {
        case .unsupportedHost:
            return "Virtualization.framework is not supported on this host."
        }
    }
}
