import Foundation

struct VMConfig: Codable {
    let cpuCount: Int
    let memoryMB: UInt64
    let kernel: String
    let initrd: String
    let disk: String
    let diskReadOnly: Bool?
    let extraDisks: [VMDiskConfig]?
    let cmdline: String

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
