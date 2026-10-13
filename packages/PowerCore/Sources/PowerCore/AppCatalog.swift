import Foundation

/// Apps WakeHold recognises by name, grouped the way the menu presents them.
/// Recognition only changes how an app is *labelled* and how eagerly it is
/// trusted — an unknown app still holds sleep if its resource use is sustained.
public enum AppCategory: String, CaseIterable, Codable, Hashable {
    case videoAudio  = "Video & Audio"
    case downloads   = "Downloads"
    case aiAgents    = "AI Agents"
    case development = "Development"
    case syncBackup  = "Sync & Backup"
    case other       = "Other"

    public var symbol: String {
        switch self {
        case .videoAudio:  return "film"
        case .downloads:   return "arrow.down.circle"
        case .aiAgents:    return "sparkles"
        case .development: return "hammer"
        case .syncBackup:  return "arrow.triangle.2.circlepath"
        case .other:       return "app.dashed"
        }
    }
}

public struct CatalogEntry {
    public let display: String
    public let category: AppCategory
    /// Bundle identifiers, matched case-insensitively.
    public let bundleIDs: [String]
    /// Executable names for command-line tools that have no bundle.
    public let executables: [String]
    /// Long jobs tolerate a gentler CPU bar before they count as working.
    public let cpuFloor: Double?

    /// Every identifier this entry can be recognised by. A catalogue entry
    /// often covers several processes — "npm / node" is five executables — so
    /// enabling or disabling it has to act on all of them at once.
    public var identifiers: [String] { bundleIDs + executables }

    public init(_ display: String, _ category: AppCategory,
         bundleIDs: [String] = [], executables: [String] = [], cpuFloor: Double? = nil) {
        self.display = display
        self.category = category
        self.bundleIDs = bundleIDs
        self.executables = executables
        self.cpuFloor = cpuFloor
    }
}

public enum AppCatalog {
    public static let entries: [CatalogEntry] = [
        // Video & audio — long renders and exports, often at low steady CPU.
        .init("Final Cut Pro", .videoAudio, bundleIDs: ["com.apple.FinalCut"], cpuFloor: 8),
        .init("Compressor", .videoAudio, bundleIDs: ["com.apple.Compressor"], cpuFloor: 8),
        .init("Motion", .videoAudio, bundleIDs: ["com.apple.motionapp"], cpuFloor: 8),
        .init("Adobe Premiere Pro", .videoAudio, bundleIDs: ["com.adobe.premierepro"], cpuFloor: 8),
        .init("Adobe Media Encoder", .videoAudio, bundleIDs: ["com.adobe.ame"], cpuFloor: 8),
        .init("After Effects", .videoAudio, bundleIDs: ["com.adobe.aftereffects"], cpuFloor: 8),
        .init("DaVinci Resolve", .videoAudio, bundleIDs: ["com.blackmagic-design.DaVinciResolve"], cpuFloor: 8),
        .init("Logic Pro", .videoAudio, bundleIDs: ["com.apple.logic10"], cpuFloor: 8),
        .init("HandBrake", .videoAudio, bundleIDs: ["fr.handbrake.HandBrake"], executables: ["HandBrakeCLI"], cpuFloor: 8),
        .init("ffmpeg", .videoAudio, executables: ["ffmpeg", "ffprobe"], cpuFloor: 5),

        // Downloads — network-dominant, CPU stays near zero.
        .init("Google Chrome", .downloads, bundleIDs: ["com.google.Chrome"]),
        .init("Safari", .downloads, bundleIDs: ["com.apple.Safari"]),
        .init("Arc", .downloads, bundleIDs: ["company.thebrowser.Browser"]),
        .init("Firefox", .downloads, bundleIDs: ["org.mozilla.firefox"]),
        .init("Microsoft Edge", .downloads, bundleIDs: ["com.microsoft.edgemac"]),
        .init("Transmission", .downloads, bundleIDs: ["org.m0k.transmission"]),
        .init("qBittorrent", .downloads, bundleIDs: ["org.qbittorrent.qBittorrent"]),
        .init("curl / wget", .downloads, executables: ["curl", "wget", "aria2c"]),

        // AI agents — bursty token streaming with long quiet gaps.
        .init("Claude Code", .aiAgents, executables: ["claude"], cpuFloor: 3),
        .init("Codex", .aiAgents, executables: ["codex"], cpuFloor: 3),
        .init("Gemini CLI", .aiAgents, executables: ["gemini"], cpuFloor: 3),
        .init("Aider", .aiAgents, executables: ["aider"], cpuFloor: 3),
        .init("Ollama", .aiAgents, bundleIDs: ["com.electron.ollama"], executables: ["ollama"], cpuFloor: 3),

        // Development — builds, containers, package installs.
        .init("Xcode", .development, bundleIDs: ["com.apple.dt.Xcode"], cpuFloor: 8),
        .init("Docker", .development, bundleIDs: ["com.docker.docker"], executables: ["com.docker.backend", "dockerd"], cpuFloor: 8),
        .init("npm / node", .development, executables: ["npm", "node", "pnpm", "yarn", "bun"], cpuFloor: 8),
        .init("cargo / rustc", .development, executables: ["cargo", "rustc"], cpuFloor: 8),
        .init("Gradle / Maven", .development, executables: ["gradle", "java", "mvn"], cpuFloor: 8),
        .init("swift / clang", .development, executables: ["swift", "swift-frontend", "clang", "ld"], cpuFloor: 8),
        .init("make / cmake", .development, executables: ["make", "cmake", "ninja"], cpuFloor: 8),
        .init("Python", .development, executables: ["python", "python3", "pip", "pip3"], cpuFloor: 8),

        // Sync & backup — steady disk plus network, frequently idle-looking.
        .init("Dropbox", .syncBackup, bundleIDs: ["com.getdropbox.dropbox"]),
        .init("Google Drive", .syncBackup, bundleIDs: ["com.google.GoogleDrive"]),
        .init("Backblaze", .syncBackup, bundleIDs: ["com.backblaze.bzbmenu"], executables: ["bzfilelist", "bztransmit"]),
        .init("iCloud Drive", .syncBackup, bundleIDs: ["com.apple.bird"], executables: ["bird", "cloudd"]),
        .init("OneDrive", .syncBackup, bundleIDs: ["com.microsoft.OneDrive"]),
        .init("Time Machine", .syncBackup, executables: ["backupd"]),
        .init("rsync", .syncBackup, executables: ["rsync", "rclone"]),
    ]

    private static let byBundle: [String: CatalogEntry] = {
        var map: [String: CatalogEntry] = [:]
        for entry in entries {
            for id in entry.bundleIDs { map[id.lowercased()] = entry }
        }
        return map
    }()

    private static let byExecutable: [String: CatalogEntry] = {
        var map: [String: CatalogEntry] = [:]
        for entry in entries {
            for name in entry.executables { map[name.lowercased()] = entry }
        }
        return map
    }()

    public static func lookup(bundleID: String?, executable: String) -> CatalogEntry? {
        if let bundleID, let hit = byBundle[bundleID.lowercased()] { return hit }
        return byExecutable[executable.lowercased()]
    }
}
