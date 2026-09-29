import Foundation

/// Formats how long a generation has been running in whole units: "12s" under a minute, then
/// "1m 5s", then "1h 2m".
public enum ElapsedTime {
    public static func string(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(total % 60)s" }
        return "\(total)s"
    }
}
