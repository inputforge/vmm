import Foundation

struct VMConfig: Codable {
    let bootMode: String
    let cpuCount: Int
    let memoryMB: UInt64

    // Linux boot fields (required when bootMode == "linux")
    let kernel: String?
    let initrd: String?
    let cmdline: String?

    // EFI boot fields (required when bootMode == "efi")
    let stateDir: String?

    let disk: String
    let diskReadOnly: Bool?
    let extraDisks: [VMDiskConfig]?
    let usbStorage: [VMDiskConfig]?
    let macAddress: String?

    static func load(from path: String) throws -> (VMConfig, URL) {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(VMConfig.self, from: data)
        return (config, url)
    }

    func resolvePath(_ path: String, relativeTo configURL: URL) -> URL {
        guard !path.hasPrefix("/") else {
            return URL(fileURLWithPath: path)
        }
        return configURL.deletingLastPathComponent().appendingPathComponent(path)
    }
}

struct VMDiskConfig: Codable {
    let path: String
    let readOnly: Bool?
}
