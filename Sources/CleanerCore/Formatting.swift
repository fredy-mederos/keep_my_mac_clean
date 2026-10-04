import Foundation

/// Byte formatting with decimal units (1 GB = 1,000,000,000 bytes), matching Finder and System Settings.
public enum ByteFormat {
    /// Compact form for the menu bar: "11 GB", "9.4 GB", "512 MB".
    public static func short(_ bytes: Int64) -> String {
        let b = Double(max(bytes, 0))
        if b >= 999.5e9 { return String(format: "%.1f TB", b / 1e12) }
        if b >= 9.95e9 { return "\(Int((b / 1e9).rounded())) GB" }
        if b >= 999.5e6 { return String(format: "%.1f GB", b / 1e9) }
        if b >= 999.5e3 { return "\(Int((b / 1e6).rounded())) MB" }
        return "\(Int((b / 1e3).rounded())) KB"
    }

    /// Standard form for lists ("13.04 GB").
    public static func standard(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }
}

public enum PathFormat {
    /// "/Users/me/Documents/x" → "~/Documents/x".
    public static func abbreviated(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
