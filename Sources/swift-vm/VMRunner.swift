import Foundation
import Virtualization

final class VMRunner: NSObject, VZVirtualMachineDelegate {
    private let vm: VZVirtualMachine
    private let stopped = DispatchSemaphore(value: 0)
    private var exitError: Error?

    init(configuration: VZVirtualMachineConfiguration) {
        self.vm = VZVirtualMachine(configuration: configuration, queue: .main)
        super.init()
        self.vm.delegate = self
    }

    func run() throws {
        guard VZVirtualMachine.isSupported else {
            throw VMRunnerError.unsupportedHost
        }

        vm.start { [weak self] result in
            switch result {
            case .success:
                break
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

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        stopped.signal()
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
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
