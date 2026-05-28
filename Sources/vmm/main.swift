import ArgumentParser
import Foundation

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
        let vmConfig = try buildConfiguration(
            from: vmConfigData,
            configURL: configURL,
            serialInput: socketManager?.vmInput ?? .standardInput,
            serialOutput: socketManager?.vmOutput ?? .standardOutput
        )

        if socketManager == nil {
            do {
                try enterRawMode()
            } catch {
                fputs("warning: failed to enter raw terminal mode: \(error)\n", stderr)
            }
        }

        let runner = VMRunner(configuration: vmConfig)
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
