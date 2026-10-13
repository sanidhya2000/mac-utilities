import Foundation
import PowerCore

/// Which apps WakeHold is allowed to stay awake for.
///
/// Stored as a set of *disabled* identifiers rather than enabled ones, so an
/// app the catalogue has never heard of is watched by default — the useful
/// behaviour, since an unknown build tool should still hold sleep.
enum WatchList {

    static func isWatched(_ identifier: String) -> Bool {
        !Prefs.shared.ignoredApps.contains(identifier)
    }

    static func setWatched(_ identifier: String, _ watched: Bool) {
        var ignored = Prefs.shared.ignoredApps
        if watched { ignored.remove(identifier) } else { ignored.insert(identifier) }
        Prefs.shared.ignoredApps = ignored
    }

    static func toggle(_ identifier: String) {
        setWatched(identifier, !isWatched(identifier))
    }

    // MARK: - Catalogue entries

    /// An entry counts as watched while any of its identifiers is still
    /// enabled, so a partially-disabled entry reads as on rather than silently
    /// appearing off while half of it is still holding sleep.
    static func isWatched(_ entry: CatalogEntry) -> Bool {
        entry.identifiers.contains(where: isWatched)
    }

    static func setWatched(_ entry: CatalogEntry, _ watched: Bool) {
        var ignored = Prefs.shared.ignoredApps
        for identifier in entry.identifiers {
            if watched { ignored.remove(identifier) } else { ignored.insert(identifier) }
        }
        Prefs.shared.ignoredApps = ignored
    }

    /// Catalogue entries grouped for display, in the order the menu lists them.
    static var byCategory: [(category: AppCategory, entries: [CatalogEntry])] {
        AppCategory.allCases.compactMap { category in
            let entries = AppCatalog.entries
                .filter { $0.category == category }
                .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
            return entries.isEmpty ? nil : (category, entries)
        }
    }

    /// Disabled identifiers that belong to no catalogue entry — apps the user
    /// turned off by clicking them in the menu. Without this they would be
    /// unreachable from Settings and could never be switched back on.
    static var disabledUnknowns: [String] {
        let known = Set(AppCatalog.entries.flatMap(\.identifiers))
        return Prefs.shared.ignoredApps.subtracting(known).sorted()
    }

    static func enableAll() { Prefs.shared.ignoredApps = [] }
}
