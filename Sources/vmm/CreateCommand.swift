import ArgumentParser
import Foundation

struct CreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new sparse raw disk image."
    )

    @Argument(help: "Path to the new disk image.")
    var path: String

    @Argument(help: "Size of the image (e.g. 10G, 512M, 1T).")
    var size: String

    func run() throws {
        let bytes = try parseSize(size)

        guard !FileManager.default.fileExists(atPath: path) else {
            throw ValidationError("\(path): file already exists")
        }

        FileManager.default.createFile(atPath: path, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(bytes))

        print("Created \(path) (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)))")
    }
}
