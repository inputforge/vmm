import Darwin
import Foundation

private var savedTermios: termios?
private var registeredTerminalRestore = false

private func restoreTerminalMode() {
    guard var saved = savedTermios else {
        return
    }

    tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved)
}

func enterRawMode() throws {
    guard isatty(STDIN_FILENO) != 0 else {
        return
    }

    var original = termios()
    guard tcgetattr(STDIN_FILENO, &original) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    savedTermios = original

    if !registeredTerminalRestore {
        atexit {
            restoreTerminalMode()
        }
        signal(SIGTERM) { _ in
            exit(128 + SIGTERM)
        }
        registeredTerminalRestore = true
    }

    var raw = original
    raw.c_lflag &= ~tcflag_t(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
    raw.c_oflag &= ~tcflag_t(OPOST)
    raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
    raw.c_cflag |= tcflag_t(CS8)

    withUnsafeMutableBytes(of: &raw.c_cc) { bytes in
        bytes[Int(VMIN)] = 1
        bytes[Int(VTIME)] = 0
    }

    guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
