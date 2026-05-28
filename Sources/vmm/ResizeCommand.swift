import ArgumentParser
import Foundation

struct ResizeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resize",
        abstract: "Resize an existing raw disk image."
    )

    @Argument(help: "Path to the disk image.")
    var path: String

    @Argument(help: "New size (e.g. 20G, 1T).")
    var size: String

    func run() throws {
        let newBytes = try parseSize(size)
        let url = URL(fileURLWithPath: path)

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let currentBytes = (attrs[.size] as? Int64) ?? 0

        if newBytes < currentBytes {
            fputs(
                "warning: shrinking \(path) from \(ByteCountFormatter.string(fromByteCount: currentBytes, countStyle: .binary))"
                    + " to \(ByteCountFormatter.string(fromByteCount: newBytes, countStyle: .binary))"
                    + " — data beyond the new size will be lost\n",
                stderr
            )
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(newBytes))

        print("Resized \(path) to \(ByteCountFormatter.string(fromByteCount: newBytes, countStyle: .binary))")
    }
}
