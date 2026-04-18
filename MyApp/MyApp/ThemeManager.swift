import SwiftUI

// MARK: - Theme Manager

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: any AppTheme = ClassicGreenTheme()
    @Published var colorScheme: ColorScheme = .dark

    let availableThemes: [any AppTheme] = [
        ClassicGreenTheme(),
    ]

    // MARK: - Convenience accessors

    var colours: ThemeColours {
        currentTheme.colours(for: effectiveScheme)
    }

    var typography: ThemeTypography {
        currentTheme.typography()
    }

    var shape: ThemeShape {
        currentTheme.shape()
    }

    var shadows: ThemeShadows {
        currentTheme.shadows(for: effectiveScheme)
    }

    var behaviour: ThemeBehaviour {
        currentTheme.behaviour()
    }

    /// The scheme actually used for colour lookups — respects fixedColorScheme.
    var effectiveScheme: ColorScheme {
        currentTheme.fixedColorScheme ?? colorScheme
    }

    /// Pass to .preferredColorScheme() at the app root.
    var preferredColorScheme: ColorScheme {
        effectiveScheme
    }

    private init() {}

    func applyTheme(_ theme: any AppTheme) {
        currentTheme = theme
        if let fixed = theme.fixedColorScheme {
            colorScheme = fixed
        } else {
            // Restore the user's saved preferred scheme when switching to an adaptive theme.
            // Without this, colorScheme remains stuck at the previous fixed scheme (e.g. .light
            // from Minimal Light), making Sunset Social / Comic Book render in the wrong mode.
            let savedMode = UserDefaults.standard.string(forKey: "preferredMode") ?? "dark"
            colorScheme = savedMode == "light" ? .light : .dark
        }
        saveTheme(theme.id)
    }

    func updateColorScheme(_ scheme: ColorScheme) {
        guard currentTheme.fixedColorScheme == nil else { return }
        colorScheme = scheme
        UserDefaults.standard.set(scheme == .dark ? "dark" : "light", forKey: "preferredMode")
    }

    func saveTheme(_ themeId: String) {
        UserDefaults.standard.set(themeId, forKey: "selectedTheme")
    }

    func loadSavedTheme() {
        let savedId = UserDefaults.standard.string(forKey: "selectedTheme") ?? "classic_green"
        let theme = availableThemes.first { $0.id == savedId } ?? ClassicGreenTheme()
        currentTheme = theme

        if let fixed = theme.fixedColorScheme {
            colorScheme = fixed
        } else {
            let savedMode = UserDefaults.standard.string(forKey: "preferredMode") ?? "dark"
            colorScheme = savedMode == "light" ? .light : .dark
        }
    }
}
