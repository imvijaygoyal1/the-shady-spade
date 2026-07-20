import Foundation

enum ShadySpadeLinks {
    static let brandedHost = "shadyspade.vijaygoyal.org"

    static func joinURL(roomCode: String) -> URL {
        URL(string: "https://\(brandedHost)/join/\(normalizedCode(roomCode))")!
    }

    static func scorekeeperURL(sessionCode: String) -> URL {
        URL(string: "https://\(brandedHost)/scorekeeper/\(normalizedCode(sessionCode))")!
    }

    static func joinInviteText(roomCode: String) -> String {
        let code = normalizedCode(roomCode)
        return """
Join my Shady Spade game! 🃏
Room Code: \(code)
Tap to join: \(joinURL(roomCode: code).absoluteString)
"""
    }

    private static func normalizedCode(_ code: String) -> String {
        let cleaned = code.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        return String(cleaned.prefix(6).uppercased())
    }
}
