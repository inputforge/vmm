import ArgumentParser
import Foundation
import QCOW2

// QCOW2 magic: "QFI\xfb"
private let qcow2Magic: [UInt8] = [0x51, 0x46, 0x49, 0xFB]

private func physicalSize(at path: String) -> Int64 {
    let url = URL(fileURLWithPath: path)
    guard let v = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]),
          let n = v.fileAllocatedSize else { return 0 }
    return Int64(n)
}

struct InfoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Print information about a disk image."
    )

    @Argument(help: "Path to the disk image.")
    var path: String

    func run() throws {
        let url = URL(fileURLWithPath: path)

        if isQCOW2(at: url) {
            try printQCOW2Info(url: url)
        } else {
            try printRawInfo(url: url)
        }
    }

    private func isQCOW2(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 4) else { return false }
        return bytes.count == 4 && [UInt8](bytes) == qcow2Magic
    }

    private func printQCOW2Info(url: URL) throws {
        let image = try QCOW2Image(url: url)
        let m = image.metadata
        let phys = physicalSize(at: url.path)

        print("Format:       QCOW2 v\(m.version)")
        print("Virtual size: \(ByteCountFormatter.string(fromByteCount: m.virtualSize, countStyle: .binary))")
        print("Disk usage:   \(ByteCountFormatter.string(fromByteCount: phys, countStyle: .binary))")
        print("Cluster size: \(ByteCountFormatter.string(fromByteCount: Int64(m.clusterSize), countStyle: .binary))")
        if let backing = m.backingFile {
            print("Backing file: \(backing)")
        }
        print("Snapshots:    \(m.snapshotCount)")
        if m.compressionType != .zlib {
            print("Compression:  \(m.compressionType)")
        }
    }

    private func printRawInfo(url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let virt = (attrs[.size] as? Int64) ?? 0
        let phys = physicalSize(at: url.path)
        print("Format:       raw")
        print("Virtual size: \(ByteCountFormatter.string(fromByteCount: virt, countStyle: .binary))")
        print("Disk usage:   \(ByteCountFormatter.string(fromByteCount: phys, countStyle: .binary))")
    }
}
