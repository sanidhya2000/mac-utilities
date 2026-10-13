import Foundation

/// Defaults mirror the tuning described on the original product page: a 300ms
/// settle before switching, a 50% turn threshold, and a 3-second pause after
/// typing stops.
final class Prefs {
    static let shared = Prefs()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let settleMilliseconds = "settleMilliseconds"
        static let turnThreshold      = "turnThreshold"
        static let paneDelayMs        = "paneDelayMilliseconds"
        static let typingPause        = "typingPauseSeconds"
        static let learnFromClicks    = "learnFromClicks"
        static let showGazeDot        = "showGazeDot"
        static let focusPanes         = "focusPanes"
        static let moveCursor         = "moveCursor"
        static let respectMouse       = "respectMouse"
        static let cameraID           = "cameraID"
        static let edgeMargin         = "edgeMarginPoints"
        static let verbose            = "verbose"
    }

    private init() {
        defaults.register(defaults: [
            Key.settleMilliseconds: 300,
            Key.turnThreshold: 50.0,
            Key.paneDelayMs: 300,
            Key.typingPause: 3.0,
            Key.learnFromClicks: true,
            Key.showGazeDot: false,
            Key.focusPanes: true,
            Key.moveCursor: true,
            Key.respectMouse: true,
            Key.edgeMargin: 40.0,
            Key.verbose: false,
        ])
    }

    /// How long the gaze must rest on a new target before focus follows, which
    /// is what stops a quick glance from stealing focus.
    var settleMilliseconds: Int {
        get { max(0, defaults.integer(forKey: Key.settleMilliseconds)) }
        set { defaults.set(newValue, forKey: Key.settleMilliseconds) }
    }

    /// How decisively the head must turn, as a percentage. Higher means the
    /// user must commit to looking away before anything happens.
    var turnThreshold: Double {
        get { defaults.double(forKey: Key.turnThreshold) }
        set { defaults.set(newValue, forKey: Key.turnThreshold) }
    }

    var paneDelayMilliseconds: Int {
        get { max(0, defaults.integer(forKey: Key.paneDelayMs)) }
        set { defaults.set(newValue, forKey: Key.paneDelayMs) }
    }

    var typingPauseSeconds: Double {
        get { defaults.double(forKey: Key.typingPause) }
        set { defaults.set(newValue, forKey: Key.typingPause) }
    }

    var learnFromClicks: Bool {
        get { defaults.bool(forKey: Key.learnFromClicks) }
        set { defaults.set(newValue, forKey: Key.learnFromClicks) }
    }

    var showGazeDot: Bool {
        get { defaults.bool(forKey: Key.showGazeDot) }
        set { defaults.set(newValue, forKey: Key.showGazeDot) }
    }

    var focusPanes: Bool {
        get { defaults.bool(forKey: Key.focusPanes) }
        set { defaults.set(newValue, forKey: Key.focusPanes) }
    }

    var moveCursor: Bool {
        get { defaults.bool(forKey: Key.moveCursor) }
        set { defaults.set(newValue, forKey: Key.moveCursor) }
    }

    var respectMouse: Bool {
        get { defaults.bool(forKey: Key.respectMouse) }
        set { defaults.set(newValue, forKey: Key.respectMouse) }
    }

    /// A band at each display edge where switching is suppressed, so a gaze
    /// hovering on a boundary cannot flicker between two screens.
    var edgeMargin: Double {
        get { defaults.double(forKey: Key.edgeMargin) }
        set { defaults.set(newValue, forKey: Key.edgeMargin) }
    }

    var cameraID: String? {
        get { defaults.string(forKey: Key.cameraID) }
        set { defaults.set(newValue, forKey: Key.cameraID) }
    }

    var verbose: Bool {
        get { defaults.bool(forKey: Key.verbose) }
        set { defaults.set(newValue, forKey: Key.verbose) }
    }
}
