import Darwin
import Foundation

final class SocketManager {
    let vmInput: FileHandle
    let vmOutput: FileHandle

    private let path: String
    private let vmInputWriter: FileHandle
    private let vmOutputReader: FileHandle
    private let queue = DispatchQueue(label: "vmm.socket-manager")
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var activeClient: Int32 = -1
    private var activeGeneration = 0
    private var isStopped = false

    init(path: String) throws {
        self.path = path

        let inputPipe = Pipe()
        vmInput = inputPipe.fileHandleForReading
        vmInputWriter = inputPipe.fileHandleForWriting

        let outputPipe = Pipe()
        vmOutputReader = outputPipe.fileHandleForReading
        vmOutput = outputPipe.fileHandleForWriting

        try startListening()
        startOutputBridge()
    }

    func stop() {
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            return
        }
        isStopped = true

        let listenerToClose = listener
        listener = -1
        let clientToClose = activeClient
        activeClient = -1
        activeGeneration += 1
        lock.unlock()

        if listenerToClose >= 0 {
            Darwin.close(listenerToClose)
        }
        if clientToClose >= 0 {
            Darwin.close(clientToClose)
        }
        unlink(path)
    }

    deinit {
        stop()
    }

    private func startListening() throws {
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxPathLength else {
            Darwin.close(fd)
            throw SocketManagerError.socketPathTooLong(path)
        }

        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            _ = path.withCString { source in
                strncpy(bytes.baseAddress!.assumingMemoryBound(to: CChar.self), source, maxPathLength - 1)
            }
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

        let bindResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            Darwin.close(fd)
            throw error
        }

        guard listen(fd, 1) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            Darwin.close(fd)
            unlink(path)
            throw error
        }

        listener = fd

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    private func acceptLoop() {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                lock.lock()
                let stopped = isStopped
                lock.unlock()
                if stopped {
                    return
                }
                continue
            }

            var yes: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

            lock.lock()
            if isStopped {
                lock.unlock()
                Darwin.close(client)
                return
            }
            let oldClient = activeClient
            activeClient = client
            activeGeneration += 1
            let generation = activeGeneration
            lock.unlock()

            if oldClient >= 0 {
                Darwin.close(oldClient)
            }

            Thread.detachNewThread { [weak self] in
                self?.clientInputLoop(client: client, generation: generation)
            }
        }
    }

    private func clientInputLoop(client: Int32, generation: Int) {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)

        while true {
            let count = Darwin.read(client, &buffer, buffer.count)
            guard count > 0 else {
                clearClient(client, generation: generation)
                return
            }

            lock.lock()
            let shouldForward = !isStopped && activeClient == client && activeGeneration == generation
            lock.unlock()

            if shouldForward {
                vmInputWriter.write(Data(buffer.prefix(count)))
            } else {
                return
            }
        }
    }

    private func startOutputBridge() {
        vmOutputReader.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.writeToActiveClient(data)
        }
    }

    private func writeToActiveClient(_ data: Data) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var offset = 0
            while offset < data.count {
                lock.lock()
                let client = activeClient
                let generation = activeGeneration
                let stopped = isStopped
                lock.unlock()

                if stopped || client < 0 {
                    return
                }

                let written = Darwin.write(client, baseAddress.advanced(by: offset), data.count - offset)
                if written > 0 {
                    offset += written
                } else {
                    clearClient(client, generation: generation)
                    return
                }
            }
        }
    }

    private func clearClient(_ client: Int32, generation: Int) {
        lock.lock()
        let shouldClose = activeClient == client && activeGeneration == generation
        if shouldClose {
            activeClient = -1
            activeGeneration += 1
        }
        lock.unlock()

        if shouldClose {
            Darwin.close(client)
        }
    }
}

enum SocketManagerError: LocalizedError {
    case socketPathTooLong(String)

    var errorDescription: String? {
        switch self {
        case .socketPathTooLong(let path):
            return "Unix socket path is too long: \(path)"
        }
    }
}
