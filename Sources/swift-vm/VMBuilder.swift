import Foundation
import Virtualization

func buildConfiguration(from config: VMConfig, configURL: URL) throws -> VZVirtualMachineConfiguration {
    let kernelURL = try resolveExistingPath(config.kernel, from: config, configURL: configURL)
    let initrdURL = try resolveExistingPath(config.initrd, from: config, configURL: configURL)
    let diskURL = try resolveExistingPath(config.disk, from: config, configURL: configURL)

    let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
    bootLoader.initialRamdiskURL = initrdURL
    bootLoader.commandLine = config.cmdline

    let vmConfig = VZVirtualMachineConfiguration()
    vmConfig.bootLoader = bootLoader
    vmConfig.cpuCount = config.cpuCount
    vmConfig.memorySize = config.memoryMB * 1024 * 1024
    let platform = VZGenericPlatformConfiguration()
    if #available(macOS 13.0, *) {
        platform.machineIdentifier = VZGenericMachineIdentifier()
    }
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
        fileHandleForReading: .standardInput,
        fileHandleForWriting: .standardOutput
    )
    let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
    serialPort.attachment = serialAttachment
    vmConfig.serialPorts = [serialPort]

    vmConfig.entropyDevices = [
        VZVirtioEntropyDeviceConfiguration()
    ]

    try vmConfig.validate()
    return vmConfig
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
        throw CocoaError(.fileNoSuchFile, userInfo: [
            NSFilePathErrorKey: url.path
        ])
    }

    return url
}
