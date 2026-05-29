import ArgumentParser
import Foundation
import Virtualization

// Breaks the circular dependency between EscapeInterceptor (needs closure at init)
// and VMRunner (doesn't exist yet when the interceptor is created). The action is
// set once, before the interceptor thread starts, so no synchronization is needed.
private final class EscapeHandle {
    var action: (() -> Void)?
    func invoke() { action?() }
}

struct VMM: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vmm",
        subcommands: [Run.self, DiskCommand.self]
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a virtual machine from a JSON configuration."
    )

    @Option(help: "Write the VM process ID to this file while running.")
    var pidFile: String?

    @Option(help: "Bridge VM console input and output through this Unix socket.")
    var socket: String?

    @Argument(help: "Path to the VM JSON configuration.")
    var config: String

    func run() throws {
        try writePIDFileIfNeeded()
        defer {
            removePIDFileIfNeeded()
        }

        let socketManager = try socket.map { try SocketManager(path: $0) }
        defer {
            socketManager?.stop()
        }

        let (vmConfigData, configURL) = try VMConfig.load(from: config)

        var escapeInterceptor: EscapeInterceptor?
        var pendingEscape: EscapeHandle?
        let serialInput: FileHandle
        if let mgr = socketManager {
            serialInput = mgr.vmInput
        } else {
            do {
                try enterRawMode()
            } catch {
                fputs("warning: failed to enter raw terminal mode: \(error)\n", stderr)
            }
            fputs("[vmm: Ctrl+A X to exit]\r\n", stderr)
            let handle = EscapeHandle()
            pendingEscape = handle
            let interceptor = EscapeInterceptor { handle.invoke() }
            escapeInterceptor = interceptor
            serialInput = interceptor.serialInput
        }

        let vmConfig = try buildConfiguration(
            from: vmConfigData,
            configURL: configURL,
            serialInput: serialInput,
            serialOutput: socketManager?.vmOutput ?? .standardOutput
        )

        let runner = VMRunner(configuration: vmConfig)
        // Wire escape directly to runner.requestStop() before starting the interceptor
        // thread, so the escape path never sends SIGTERM and has no handler-install race.
        pendingEscape?.action = { runner.requestStop() }
        escapeInterceptor?.start()
        try runner.run()
    }

    private func writePIDFileIfNeeded() throws {
        guard let pidFile else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        try "\(pid)\n".write(toFile: pidFile, atomically: true, encoding: .utf8)
    }

    private func removePIDFileIfNeeded() {
        guard let pidFile else { return }
        try? FileManager.default.removeItem(atPath: pidFile)
    }
}

VMM.main()
