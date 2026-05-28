import ArgumentParser
import Darwin
import Foundation

struct CloneCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clone",
        abstract: "Clone a disk image (copy-on-write on APFS, regular copy otherwise)."
    )

    @Argument(help: "Path to the source disk image.")
    var source: String

    @Argument(help: "Path to the destination disk image.")
    var destination: String

    func run() throws {
        guard !FileManager.default.fileExists(atPath: destination) else {
            throw ValidationError("\(destination): file already exists")
        }

        if clonefile(source, destination, 0) == 0 {
            print("Cloned \(source) → \(destination) (copy-on-write)")
            return
        }

        let err = errno
        guard err == ENOTSUP || err == EXDEV else {
            let code = POSIXError.Code(rawValue: err) ?? .EIO
            throw POSIXError(code)
        }

        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: source),
            to: URL(fileURLWithPath: destination)
        )
        print("Cloned \(source) → \(destination) (full copy)")
    }
}
