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
    var vmPersistedMAC: VZMACAddress? = nil

    switch config.bootMode {
    case "linux":
        guard let kernelPath = config.kernel,
              let cmdline = config.cmdline else {
            throw ConfigError("bootMode 'linux' requires 'kernel' and 'cmdline'")
        }
        let kernelURL = try resolveExistingPath(kernelPath, from: config, configURL: configURL)
        let loader = VZLinuxBootLoader(kernelURL: kernelURL)
        if let initrdPath = config.initrd {
            loader.initialRamdiskURL = try resolveExistingPath(initrdPath, from: config, configURL: configURL)
        }
        loader.commandLine = cmdline
        bootLoader = loader
        platform.machineIdentifier = VZGenericMachineIdentifier()

    case "efi":
        guard let stateDirPath = config.stateDir else {
            throw ConfigError("bootMode 'efi' requires 'stateDir'")
        }
        let stateDirURL = config.resolvePath(stateDirPath, relativeTo: configURL)
        let (nvramURL, machineIDURL, persistedMAC) = try bootstrapStateDir(stateDirURL)

        let variableStore = VZEFIVariableStore(url: nvramURL)
        let loader = VZEFIBootLoader()
        loader.variableStore = variableStore
        bootLoader = loader

        let machineIDData = try Data(contentsOf: machineIDURL)
        guard let machineID = VZGenericMachineIdentifier(dataRepresentation: machineIDData) else {
            throw ConfigError("invalid machine identifier in \(machineIDURL.path)")
        }
        platform.machineIdentifier = machineID
        vmPersistedMAC = persistedMAC

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
    if let mac = vmPersistedMAC {
        networkDevice.macAddress = mac
    }
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

// Returns (nvramURL, machineIDURL, macAddress). Creates the directory and all files on first run.
// Errors if directory exists but any required file is missing.
private func bootstrapStateDir(_ dir: URL) throws -> (URL, URL, VZMACAddress) {
    let nvramURL = dir.appendingPathComponent("nvram.bin")
    let machineIDURL = dir.appendingPathComponent("machineid")
    let macAddrURL = dir.appendingPathComponent("macaddr")
    let fm = FileManager.default

    let dirExists = fm.fileExists(atPath: dir.path)
    let nvramExists = fm.fileExists(atPath: nvramURL.path)
    let machineIDExists = fm.fileExists(atPath: machineIDURL.path)
    let macAddrExists = fm.fileExists(atPath: macAddrURL.path)

    if dirExists {
        var missing: [String] = []
        if !nvramExists { missing.append("nvram.bin") }
        if !machineIDExists { missing.append("machineid") }
        if !missing.isEmpty {
            throw ConfigError("stateDir '\(dir.path)' exists but is missing: \(missing.joined(separator: ", "))")
        }
        let macAddress: VZMACAddress
        if macAddrExists {
            let macString = try String(contentsOf: macAddrURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let mac = VZMACAddress(string: macString) else {
                throw ConfigError("invalid MAC address in \(macAddrURL.path)")
            }
            macAddress = mac
        } else {
            // Migrate existing state dir: generate and persist a MAC
            macAddress = VZMACAddress.randomLocallyAdministered()
            try macAddress.string.write(to: macAddrURL, atomically: true, encoding: .utf8)
        }
        return (nvramURL, machineIDURL, macAddress)
    }

    // First run: create directory + all state files
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    _ = try VZEFIVariableStore(creatingVariableStoreAt: nvramURL)
    let machineID = VZGenericMachineIdentifier()
    try machineID.dataRepresentation.write(to: machineIDURL)
    let macAddress = VZMACAddress.randomLocallyAdministered()
    try macAddress.string.write(to: macAddrURL, atomically: true, encoding: .utf8)
    return (nvramURL, machineIDURL, macAddress)
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
