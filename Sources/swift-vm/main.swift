import Foundation

func usage() {
    fputs("usage: swift-vm run <config.json>\n", stderr)
}

guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "run" else {
    usage()
    exit(1)
}

let configPath = CommandLine.arguments[2]

do {
    let (config, configURL) = try VMConfig.load(from: configPath)
    let vmConfig = try buildConfiguration(from: config, configURL: configURL)

    do {
        try enterRawMode()
    } catch {
        fputs("warning: failed to enter raw terminal mode: \(error)\n", stderr)
    }

    let runner = VMRunner(configuration: vmConfig)
    try runner.run()
    exit(0)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
