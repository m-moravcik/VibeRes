import Foundation

extension Locale {
    /// The app's language with the user's region: the locale every localised
    /// string should be resolved and formatted in.
    ///
    /// `Locale.current` follows the system's Language & Region settings, not
    /// the language the app runs in. When Czech is chosen for VibeRes alone
    /// (System Settings → Language & Region → Applications) on an English-locale
    /// Mac, the strings come from the Czech table but the plural rules would be
    /// English, which has no "few", so 2–4 rendered as "3 displejů" instead of
    /// "3 displeje". Taking the language from the localisation the bundle
    /// actually loaded keeps the plural rules in step with the strings; keeping
    /// the region keeps the user's number and date formats.
    ///
    /// SwiftUI picks it up through `\.locale`, set at the root of the popover
    /// and the Settings window. Strings resolved outside a view, such as
    /// `ApplyOutcomeNote`, have to pass it to `LocalizedStringResource`.
    static var appLanguage: Locale {
        appLanguage(Bundle.main.preferredLocalizations.first, region: .current)
    }

    static func appLanguage(_ localization: String?, region base: Locale) -> Locale {
        guard let localization else { return base }
        let language = Locale.Language(identifier: localization)
        var components = Locale.Components(locale: base)
        components.languageComponents.languageCode = language.languageCode
        components.languageComponents.script = language.script
        return Locale(components: components)
    }
}
