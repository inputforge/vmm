import Foundation
import Virtualization

func buildConfiguration(
    from config: VMConfig,
    configURL: URL,
    serialInput: FileHandle = .standardInput,
    serialOutput: FileHandle = .standardOutput
) throws -> VZVirtualMachineConfiguration {
    let bootLoader: VZBootLoader
    let platform = VZGenericPlatformConfiguration()

    switch config.bootMode {
    case "linux":
        guard let kernelPath = config.kernel,
              let initrdPath = config.initrd,
              let cmdline = config.cmdline else {
            throw ConfigError("bootMode 'linux' requires 'kernel', 'initrd', and 'cmdline'")
        }
        let kernelURL = try resolveExistingPath(kernelPath, from: config, configURL: configURL)
        let initrdURL = try resolveExistingPath(initrdPath, from: config, configURL: configURL)
        let loader = VZLinuxBootLoader(kernelURL: kernelURL)
        loader.initialRamdiskURL = initrdURL
        loader.commandLine = cmdline
        bootLoader = loader
        platform.machineIdentifier = VZGenericMachineIdentifier()

    case "efi":
        guard let stateDirPath = config.stateDir else {
            throw ConfigError("bootMode 'efi' requires 'stateDir'")
        }
        let stateDirURL = config.resolvePath(stateDirPath, relativeTo: configURL)
        let (nvramURL, machineIDURL) = try bootstrapStateDir(stateDirURL)

        let variableStore = VZEFIVariableStore(url: nvramURL)
        let loader = VZEFIBootLoader()
        loader.variableStore = variableStore
        bootLoader = loader

        let machineIDData = try Data(contentsOf: machineIDURL)
        guard let machineID = VZGenericMachineIdentifier(dataRepresentation: machineIDData) else {
            throw ConfigError("invalid machine identifier in \(machineIDURL.path)")
        }
        platform.machineIdentifier = machineID

    default:
        throw ConfigError("unknown bootMode '\(config.bootMode)'; expected 'linux' or 'efi'")
    }

    let diskURL = try resolveExistingPath(config.disk, from: config, configURL: configURL)

    let vmConfig = VZVirtualMachineConfiguration()
    vmConfig.bootLoader = bootLoader
    vmConfig.cpuCount = config.cpuCount
    vmConfig.memorySize = config.memoryMB * 1024 * 1024
    vmConfig.platform = platform

    var storageDevices: [VZStorageDeviceConfiguration] = [
        try buildStorageDevice(url: diskURL, readOnly: config.diskReadOnly ?? false)
    ]
    for disk in config.extraDisks ?? [] {
        let url = try resolveExistingPath(disk.path, from: config, configURL: configURL)
        storageDevices.append(try buildStorageDevice(url: url, readOnly: disk.readOnly ?? false))
    }
    vmConfig.storageDevices = storageDevices

    let networkDevice = VZVirtioNetworkDeviceConfiguration()
    networkDevice.attachment = VZNATNetworkDeviceAttachment()
    vmConfig.networkDevices = [networkDevice]

    let serialAttachment = VZFileHandleSerialPortAttachment(
        fileHandleForReading: serialInput,
        fileHandleForWriting: serialOutput
    )
    let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
    serialPort.attachment = serialAttachment
    vmConfig.serialPorts = [serialPort]

    vmConfig.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

    try vmConfig.validate()
    return vmConfig
}

// Returns (nvramURL, machineIDURL). Creates the directory and both files on first run.
// Errors if directory exists but either file is missing.
private func bootstrapStateDir(_ dir: URL) throws -> (URL, URL) {
    let nvramURL = dir.appendingPathComponent("nvram.bin")
    let machineIDURL = dir.appendingPathComponent("machineid")
    let fm = FileManager.default

    let dirExists = fm.fileExists(atPath: dir.path)
    let nvramExists = fm.fileExists(atPath: nvramURL.path)
    let machineIDExists = fm.fileExists(atPath: machineIDURL.path)

    if dirExists {
        if !nvramExists || !machineIDExists {
            var missing: [String] = []
            if !nvramExists { missing.append("nvram.bin") }
            if !machineIDExists { missing.append("machineid") }
            throw ConfigError("stateDir '\(dir.path)' exists but is missing: \(missing.joined(separator: ", "))")
        }
        return (nvramURL, machineIDURL)
    }

    // First run: create directory + both files
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    _ = try VZEFIVariableStore(creatingVariableStoreAt: nvramURL)
    let machineID = VZGenericMachineIdentifier()
    try machineID.dataRepresentation.write(to: machineIDURL)
    return (nvramURL, machineIDURL)
}

private func buildStorageDevice(url: URL, readOnly: Bool) throws -> VZVirtioBlockDeviceConfiguration {
    let attachment = try VZDiskImageStorageDeviceAttachment(
        url: url,
        readOnly: readOnly,
        cachingMode: .automatic,
        synchronizationMode: .fsync
    )
    return VZVirtioBlockDeviceConfiguration(attachment: attachment)
}

private func resolveExistingPath(_ path: String, from config: VMConfig, configURL: URL) throws -> URL {
    let url = config.resolvePath(path, relativeTo: configURL)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
    }
    return url
}

struct ConfigError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
}
