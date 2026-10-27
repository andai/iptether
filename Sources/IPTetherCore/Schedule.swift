import Foundation

/// A local time of day written "HH:mm", used for the daily full sweep.
public struct DailyTime: Equatable, Sendable {
    public var hour: Int
    public var minute: Int

    public init?(_ text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[0].count <= 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        hour = h
        minute = m
    }

    /// The first moment strictly after `date` at this time of day.
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime
        )
    }
}
