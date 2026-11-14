import Foundation

// Localised names for a profile's entries. In VibeRes/UI rather than next to
// `Profile` because VibeRes/Core is also compiled into the bundle-less
// `viberes` tool, where a String Catalog lookup does not resolve (see
// `ApplyOutcomeNote`).

extension Profile.Entry {
    /// The display this entry is for, as the user reads it: the name saved
    /// with it, or "any external monitor" for an entry that takes whichever
    /// external is there.
    func localizedDisplayName(locale: Locale = .appLanguage) -> String {
        if case .anyExternal = matcher {
            return String(localized: LocalizedStringResource(
                "profile.entry.anyExternal",
                defaultValue: "any external monitor",
                locale: locale,
                comment: "Stands for a profile entry that applies to whichever external monitor is connected"
            ))
        }
        return displayName
    }
}

extension Profile {
    /// The displays the profile names, in order, each once.
    func localizedDisplayNames(locale: Locale = .appLanguage) -> [String] {
        ProfileCopy.displayNames(of: entries, locale: locale)
    }

    /// "Built-in Retina Display + any external monitor", for the pill's
    /// tooltip.
    func localizedSummary(locale: Locale = .appLanguage) -> String {
        localizedDisplayNames(locale: locale).joined(separator: " + ")
    }
}

enum ProfileCopy {
    /// The displays the entries stand for, in order, each once: two entries
    /// saved from twin monitors read as one name.
    static func displayNames(of entries: [Profile.Entry], locale: Locale = .appLanguage) -> [String] {
        var seen = Set<String>()
        return entries.map { $0.localizedDisplayName(locale: locale) }.filter { seen.insert($0).inserted }
    }

    /// "A, B and C" in the app's language.
    static func list(_ names: [String], locale: Locale = .appLanguage) -> String {
        names.formatted(.list(type: .and).locale(locale))
    }
}
