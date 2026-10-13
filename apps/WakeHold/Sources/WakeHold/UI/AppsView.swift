import SwiftUI
import PowerCore

/// Two lists: what WakeHold stays awake for, and what it ignores. Clicking any
/// row moves it to the other list.
///
/// The original product hides this behind a hover action in the menu plus a
/// separate "ignored" pane in settings, which makes the current state hard to
/// read. Showing both sides at once means the answer to "what is holding my Mac
/// awake?" is always on screen.
struct AppsView: View {
    @ObservedObject var engine: WakeEngine

    @State private var search = ""
    @State private var version = 0

    /// One row, resolved from either the catalogue or a live process.
    private struct Entry: Identifiable {
        let id: String
        let name: String
        let detail: String?
        let category: AppCategory
        /// Busy right now, so the row can show a live indicator.
        let isWorking: Bool
    }

    // MARK: - Data

    /// Every app we can offer, catalogue plus anything seen working or already
    /// switched off, so nothing is ever unreachable.
    private var allEntries: [Entry] {
        var byID: [String: Entry] = [:]

        for item in AppCatalog.entries {
            guard let id = item.identifiers.first else { continue }
            byID[id] = Entry(id: id, name: item.display, detail: nil,
                             category: item.category, isWorking: false)
        }

        // Live processes override the catalogue row so the reason shows.
        for app in engine.busyApps {
            byID[app.id] = Entry(id: app.id, name: app.display, detail: app.reason,
                                 category: app.category, isWorking: true)
        }

        // Anything switched off that we would not otherwise list.
        for id in Prefs.shared.ignoredApps where byID[id] == nil {
            let known = AppCatalog.lookup(bundleID: id, executable: id)
            byID[id] = Entry(id: id, name: known?.display ?? id, detail: known == nil ? "not in catalogue" : nil,
                             category: known?.category ?? .other, isWorking: false)
        }

        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return byID.values
            .filter { query.isEmpty || $0.name.lowercased().contains(query) }
            .sorted {
                // Working apps float to the top; the rest alphabetical.
                if $0.isWorking != $1.isWorking { return $0.isWorking }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var watched: [Entry] { allEntries.filter { WatchList.isWatched($0.id) } }
    private var ignored: [Entry] { allEntries.filter { !WatchList.isWatched($0.id) } }

    // MARK: - View

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            List {
                section(title: "Staying awake for",
                        subtitle: "These can hold your Mac awake",
                        symbol: "cup.and.saucer.fill",
                        entries: watched,
                        empty: "Nothing is being watched — your Mac will sleep normally.",
                        moveSymbol: "arrow.down.circle",
                        moveHint: "Stop staying awake for this")

                section(title: "Not watching",
                        subtitle: "Ignored, however busy they get",
                        symbol: "moon.zzz",
                        entries: ignored,
                        empty: "Nothing ignored.",
                        moveSymbol: "arrow.up.circle",
                        moveHint: "Stay awake for this again")
            }
            .listStyle(.inset)
            .id(version)

            Divider()
            footer
        }
        .frame(width: 480, height: 580)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Choose Apps").font(.headline)
            Text("Click any app to move it between the two lists.")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(16)
    }

    @ViewBuilder
    private func section(title: String, subtitle: String, symbol: String,
                         entries: [Entry], empty: String,
                         moveSymbol: String, moveHint: String) -> some View {
        Section {
            if entries.isEmpty {
                Text(empty).font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    row(entry, moveSymbol: moveSymbol, hint: moveHint)
                }
            }
        } header: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title)
                Text("\(entries.count)")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.14))
                    .clipShape(Capsule())
                Spacer()
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ entry: Entry, moveSymbol: String, hint: String) -> some View {
        Button {
            WatchList.setWatched(entry.id, !WatchList.isWatched(entry.id))
            bump()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.category.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 17)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.name).lineLimit(1).truncationMode(.middle)
                        if entry.isWorking {
                            // A live dot makes it obvious which rows are the
                            // reason the Mac is awake right now.
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                        }
                    }
                    if let detail = entry.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }

                Spacer()
                Image(systemName: moveSymbol).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
    }

    private var footer: some View {
        HStack {
            Text(ignored.isEmpty
                 ? "Watching everything"
                 : "\(ignored.count) ignored")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Watch everything") {
                WatchList.enableAll()
                bump()
            }
            .disabled(ignored.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    /// WatchList is backed by UserDefaults, which SwiftUI cannot observe.
    private func bump() {
        version += 1
        engine.refresh()
    }
}
