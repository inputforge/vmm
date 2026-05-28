import ArgumentParser
import Foundation
import QCOW2

struct DiskCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disk",
        abstract: "Disk image utilities.",
        subcommands: [ConvertCommand.self, CreateCommand.self, ResizeCommand.self, InfoCommand.self, CloneCommand.self]
    )
}

struct ConvertCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert a QCOW2 disk image to a raw disk image."
    )

    @Argument(help: "Path to the input QCOW2 image.")
    var input: String

    @Argument(help: "Path to the output raw disk image.")
    var output: String

    func run() throws {
        let sema = DispatchSemaphore(value: 0)
        var thrownError: Error?
        Task {
            do {
                try await convert()
            } catch {
                thrownError = error
            }
            sema.signal()
        }
        sema.wait()
        if let error = thrownError { throw error }
    }

    private func convert() async throws {
        let inputURL  = URL(fileURLWithPath: input).resolvingSymlinksInPath()
        let outputURL = URL(fileURLWithPath: output).resolvingSymlinksInPath()
        guard inputURL != outputURL else {
            throw ValidationError("input and output are the same file")
        }
        guard !FileManager.default.fileExists(atPath: output) else {
            throw ValidationError("\(output): file already exists")
        }

        let image = try QCOW2Image(url: URL(fileURLWithPath: input))
        let totalSize = image.size

        guard totalSize > 0 else {
            throw ValidationError("image reports zero size")
        }

        print("Input:  \(input)")
        print("Output: \(output)")
        print("Size:   \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .binary))")

        FileManager.default.createFile(atPath: output, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: output))
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(totalSize))
        let fd = handle.fileDescriptor

        let chunkSize = 1024 * 1024
        let totalChunks = Int((totalSize + Int64(chunkSize) - 1) / Int64(chunkSize))
        let parallelism = ProcessInfo.processInfo.activeProcessorCount
        let progress = ProgressReporter(totalChunks: totalChunks)

        try await withThrowingTaskGroup(of: Void.self) { group in
            var inFlight = 0
            for i in 0..<totalChunks {
                if inFlight >= parallelism {
                    try await group.next()
                    inFlight -= 1
                }
                group.addTask {
                    let offset = Int64(i) * Int64(chunkSize)
                    let count = Int(min(Int64(chunkSize), totalSize - offset))
                    let result = try image.readAtWithZeroStatus(offset: offset, count: count)
                    if !result.isZero {
                        try pwriteAll(fd: fd, data: result.data, offset: offset)
                    }
                    await progress.completedChunk()
                }
                inFlight += 1
            }
            try await group.waitForAll()
        }

        print("\nDone.")
    }
}

private func pwriteAll(fd: Int32, data: Data, offset: Int64) throws {
    try data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) throws in
        var remaining = ptr.count
        var done = 0
        while remaining > 0 {
            let n = pwrite(fd, ptr.baseAddress! + done, remaining, offset + Int64(done))
            if n < 0 {
                let code = POSIXError.Code(rawValue: errno) ?? .EIO
                throw POSIXError(code)
            }
            done += n
            remaining -= n
        }
    }
}

private actor ProgressReporter {
    private let totalChunks: Int
    private var completedChunks = 0
    private var lastPrintedPercent = -1

    init(totalChunks: Int) {
        self.totalChunks = totalChunks
    }

    func completedChunk() {
        completedChunks += 1
        let pct = 100 * completedChunks / totalChunks
        guard pct != lastPrintedPercent else { return }
        lastPrintedPercent = pct
        print("\r\(pct)%", terminator: "")
        fflush(stdout)
    }
}
