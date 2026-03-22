import Foundation

enum ProfanityFilter {

    // Common English profanity — mirrors the server-side bad-words check.
    // Kept as a Set<String> for O(1) lookup.
    private static let wordList: Set<String> = [
        "fuck", "shit", "ass", "asshole", "bitch", "cunt", "dick",
        "cock", "pussy", "bastard", "damn", "hell", "crap", "piss",
        "fag", "faggot", "slut", "whore", "nigga", "nigger", "retard",
        "motherfucker", "fucker", "bullshit", "jackass", "dumbass",
        "dipshit", "horseshit", "shithead", "fuckhead", "arsehole",
        "arse", "wank", "wanker", "twat", "bollocks", "prick",
    ]

    // Normalise common leet-speak substitutions before checking.
    private static func normalise(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "@", with: "a")
            .replacingOccurrences(of: "4", with: "a")
            .replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "1", with: "i")
            .replacingOccurrences(of: "3", with: "e")
            .replacingOccurrences(of: "$", with: "s")
            .replacingOccurrences(of: "!", with: "i")
            .replacingOccurrences(of: "5", with: "s")
            .replacingOccurrences(of: "7", with: "t")
    }

    /// Returns `true` if the text contains profanity.
    static func isProfane(_ text: String) -> Bool {
        let norm = normalise(text)
        return wordList.contains { norm.contains($0) }
    }
}
