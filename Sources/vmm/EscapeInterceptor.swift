import Darwin
import Foundation

// Reads stdin and forwards bytes to a pipe, intercepting Ctrl+A escape sequences:
//   Ctrl+A X       — calls onEscape() and stops forwarding (exit signal)
//   Ctrl+A Ctrl+A  — sends one literal Ctrl+A to the guest
//   Ctrl+A <other> — sends Ctrl+A + <other> unchanged
private let ctrlA: UInt8 = 0x01

final class EscapeInterceptor {
    let serialInput: FileHandle

    private let pipe = Pipe()
    private let onEscape: () -> Void

    init(onEscape: @escaping () -> Void) {
        self.serialInput = pipe.fileHandleForReading
        self.onEscape = onEscape
    }

    func start() {
        let writeEnd = pipe.fileHandleForWriting
        Thread.detachNewThread { self.readLoop(writeEnd: writeEnd) }
    }

    private func readLoop(writeEnd: FileHandle) {
        var escaped = false
        var buf = [UInt8](repeating: 0, count: 4096)

        while true {
            let n = Darwin.read(STDIN_FILENO, &buf, buf.count)
            guard n > 0 else {
                onEscape()
                return
            }

            var out = [UInt8]()
            out.reserveCapacity(n)

            for i in 0..<n {
                let byte = buf[i]
                if escaped {
                    escaped = false
                    switch byte {
                    case UInt8(ascii: "x"), UInt8(ascii: "X"):
                        fputs("\r\n[vmm: detaching]\r\n", stderr)
                        onEscape()
                        return
                    case ctrlA:
                        out.append(ctrlA)
                    default:
                        out.append(ctrlA)
                        out.append(byte)
                    }
                } else if byte == ctrlA {
                    escaped = true
                } else {
                    out.append(byte)
                }
            }

            if !out.isEmpty {
                writeEnd.write(Data(out))
            }
        }
    }
}
