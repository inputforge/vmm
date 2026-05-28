import ArgumentParser

// Longest suffixes first so "GiB" matches before "G".
private let sizeSuffixes: [(String, Int64)] = [
    ("TIB", 1 << 40), ("GIB", 1 << 30), ("MIB", 1 << 20), ("KIB", 1 << 10),
    ("T", 1 << 40), ("G", 1 << 30), ("M", 1 << 20), ("K", 1 << 10), ("B", 1),
]

func parseSize(_ s: String) throws -> Int64 {
    let upper = s.uppercased()
    for (suffix, multiplier) in sizeSuffixes {
        guard upper.hasSuffix(suffix) else { continue }
        let numStr = String(upper.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        guard !numStr.isEmpty, let n = Double(numStr), n > 0 else { continue }
        let result = Int64(n * Double(multiplier))
        guard result > 0 else { continue }
        return result
    }
    guard let n = Int64(s.trimmingCharacters(in: .whitespaces)), n > 0 else {
        throw ValidationError("Invalid size '\(s)'. Examples: 10G, 512M, 1T, 1073741824.")
    }
    return n
}
