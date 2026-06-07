import SwiftUI

// MARK: - Theme Manager

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: any AppTheme = ClassicGreenTheme()
    @Published var colorScheme: ColorScheme = .dark
    @Published var themeMode: ThemeMode = .dark

    let availableThemes: [any AppTheme] = [
        ClassicGreenTheme(),
        MidnightBlueTheme(),
        ParchmentTheme(),
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
    var preferredColorScheme: ColorScheme? {
        currentTheme.fixedColorScheme ?? themeMode.forcedColorScheme
    }

    private init() {}

    func applyTheme(_ theme: any AppTheme) {
        currentTheme = theme
        if let fixed = theme.fixedColorScheme {
            colorScheme = fixed
        } else {
            applyStoredMode()
        }
        saveTheme(theme.id)
    }

    func updateColorScheme(_ scheme: ColorScheme) {
        guard currentTheme.fixedColorScheme == nil else { return }
        themeMode = scheme == .dark ? .dark : .light
        colorScheme = scheme
        UserDefaults.standard.set(themeMode.rawValue, forKey: "preferredMode")
    }

    func updateThemeMode(_ mode: ThemeMode) {
        guard currentTheme.fixedColorScheme == nil else { return }
        themeMode = mode
        if let forced = mode.forcedColorScheme {
            colorScheme = forced
        }
        UserDefaults.standard.set(mode.rawValue, forKey: "preferredMode")
    }

    func updateSystemColorScheme(_ scheme: ColorScheme) {
        guard currentTheme.fixedColorScheme == nil, themeMode == .system else { return }
        colorScheme = scheme
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
            applyStoredMode()
        }
    }

    private func applyStoredMode() {
        let savedMode = UserDefaults.standard.string(forKey: "preferredMode") ?? ThemeMode.dark.rawValue
        themeMode = ThemeMode(rawValue: savedMode) ?? .dark
        if let forced = themeMode.forcedColorScheme {
            colorScheme = forced
        }
    }
}
