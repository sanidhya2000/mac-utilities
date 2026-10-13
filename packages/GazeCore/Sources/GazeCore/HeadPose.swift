import Foundation

/// One reading of where the head is and which way it is turned.
public struct HeadPose {
    /// Left/right rotation in radians; positive is turning to the user's left.
    public let yaw: Double
    /// Up/down rotation in radians.
    public let pitch: Double
    public let roll: Double
    /// Face centre within the frame, 0–1, origin bottom-left.
    public let centerX: Double
    public let centerY: Double
    /// Face box area as a fraction of the frame — a proxy for distance, used to
    /// notice when someone has moved closer or further than when they calibrated.
    public let area: Double
    public let timestamp: Date

    public init(yaw: Double, pitch: Double, roll: Double,
                centerX: Double, centerY: Double, area: Double, timestamp: Date) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.centerX = centerX
        self.centerY = centerY
        self.area = area
        self.timestamp = timestamp
    }

    /// The feature vector the screen mapping is fitted against. Yaw alone is a
    /// weak signal because people turn their eyes as well as their head, so the
    /// face's position in frame is included — it shifts measurably when someone
    /// looks across to another display.
    public var features: [Double] { [1, yaw, pitch, centerX, centerY] }

    public static let featureCount = 5
}
