import Foundation

/// One recorded state from `history/history_during_period`.
public struct HAHistoryPoint: Hashable, Sendable {
    public let time: Date
    public let state: String

    public init(time: Date, state: String) {
        self.time = time
        self.state = state
    }

    /// The numeric value, if the state is a number.
    public var value: Double? { Double(state) }
}

/// One aggregated period from `recorder/statistics_during_period`.
public struct HAStatisticPoint: Hashable, Sendable {
    public let start: Date
    public var mean: Double?
    public var min: Double?
    public var max: Double?
    public var sum: Double?
    public var state: Double?
    public var change: Double?

    public init(
        start: Date, mean: Double? = nil, min: Double? = nil, max: Double? = nil,
        sum: Double? = nil, state: Double? = nil, change: Double? = nil
    ) {
        self.start = start
        self.mean = mean
        self.min = min
        self.max = max
        self.sum = sum
        self.state = state
        self.change = change
    }

    public func value(for type: String) -> Double? {
        switch type {
        case "mean": return mean
        case "min": return min
        case "max": return max
        case "sum": return sum
        case "state": return state
        case "change": return change
        default: return nil
        }
    }
}

public enum HAHistoryParser {
    /// Parses a history result keyed by entity ID. Handles both the compressed
    /// (`s`/`lu`/`lc`, seconds since epoch) and full (`state`/`last_changed`) formats.
    public static func history(_ result: JSONValue) -> [String: [HAHistoryPoint]] {
        var history: [String: [HAHistoryPoint]] = [:]
        for (entityId, states) in result.objectValue ?? [:] {
            history[entityId] = (states.arrayValue ?? []).compactMap { item in
                guard let state = item["s"]?.stringValue ?? item["state"]?.stringValue,
                      let time = date(item["lc"]) ?? date(item["lu"])
                          ?? date(item["last_changed"]) ?? date(item["last_updated"])
                else { return nil }
                return HAHistoryPoint(time: time, state: state)
            }
        }
        return history
    }

    /// Parses a statistics result keyed by statistic ID. `start` is milliseconds
    /// since epoch in current versions, an ISO date in older ones.
    public static func statistics(_ result: JSONValue) -> [String: [HAStatisticPoint]] {
        var statistics: [String: [HAStatisticPoint]] = [:]
        for (id, rows) in result.objectValue ?? [:] {
            statistics[id] = (rows.arrayValue ?? []).compactMap { row in
                guard let start = date(row["start"], numbersAreMilliseconds: true) else { return nil }
                return HAStatisticPoint(
                    start: start,
                    mean: row["mean"]?.doubleValue,
                    min: row["min"]?.doubleValue,
                    max: row["max"]?.doubleValue,
                    sum: row["sum"]?.doubleValue,
                    state: row["state"]?.doubleValue,
                    change: row["change"]?.doubleValue
                )
            }
        }
        return statistics
    }

    static func date(_ value: JSONValue?, numbersAreMilliseconds: Bool = false) -> Date? {
        switch value {
        case .number(let number):
            return Date(timeIntervalSince1970: numbersAreMilliseconds ? number / 1000 : number)
        case .string(let text):
            return parseISODate(text)
        default:
            return nil
        }
    }

    public static func parseISODate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    public static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public enum HADownsampler {
    /// Reduces a numeric series to at most `maxCount` points by averaging equal
    /// time buckets, so long histories stay fast to draw. Non-numeric points are dropped.
    public static func numeric(_ points: [HAHistoryPoint], maxCount: Int) -> [(time: Date, value: Double)] {
        let numeric = points.compactMap { point in point.value.map { (time: point.time, value: $0) } }
        guard numeric.count > maxCount, maxCount > 0,
              let first = numeric.first?.time, let last = numeric.last?.time, last > first
        else { return numeric }

        let width = last.timeIntervalSince(first) / Double(maxCount)
        var buckets: [Int: (sum: Double, count: Int, time: Date)] = [:]
        for point in numeric {
            let index = Swift.min(Int(point.time.timeIntervalSince(first) / width), maxCount - 1)
            let bucket = buckets[index] ?? (0, 0, point.time)
            buckets[index] = (bucket.sum + point.value, bucket.count + 1, bucket.time)
        }
        return buckets.keys.sorted().map { key in
            let bucket = buckets[key]!
            return (bucket.time, bucket.sum / Double(bucket.count))
        }
    }

    /// Merges consecutive statistics so there are at most `maxCount`, keeping
    /// the overall min/max and averaging the mean.
    public static func statistics(_ points: [HAStatisticPoint], maxCount: Int) -> [HAStatisticPoint] {
        guard points.count > maxCount, maxCount > 0 else { return points }
        let size = Int((Double(points.count) / Double(maxCount)).rounded(.up))
        return stride(from: 0, to: points.count, by: size).map { start in
            let chunk = points[start..<Swift.min(start + size, points.count)]
            func average(_ values: [Double]) -> Double? {
                values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            }
            let changes = chunk.compactMap(\.change)
            return HAStatisticPoint(
                start: chunk.first!.start,
                mean: average(chunk.compactMap(\.mean)),
                min: chunk.compactMap(\.min).min(),
                max: chunk.compactMap(\.max).max(),
                sum: chunk.last?.sum,
                state: chunk.last?.state,
                change: changes.isEmpty ? nil : changes.reduce(0, +)
            )
        }
    }
}

/// What the Energy dashboard tracks (`energy/get_prefs`).
public struct HAEnergyPrefs: Sendable, Hashable {
    public struct Device: Sendable, Hashable, Identifiable {
        public let statistic: String
        public let name: String?
        public var id: String { statistic }
    }

    /// Energy drawn from the grid.
    public let gridImports: [String]
    /// Energy returned to the grid.
    public let gridExports: [String]
    public let solar: [String]
    /// Individual devices' consumption.
    public let devices: [Device]

    public init(_ json: JSONValue) {
        let sources = json["energy_sources"]?.arrayValue ?? []
        var imports: [String] = [], exports: [String] = [], solar: [String] = []
        for source in sources {
            switch source["type"]?.stringValue {
            case "grid":
                imports += (source["flow_from"]?.arrayValue ?? []).compactMap { $0["stat_energy_from"]?.stringValue }
                exports += (source["flow_to"]?.arrayValue ?? []).compactMap { $0["stat_energy_to"]?.stringValue }
                // Newer releases list one grid source per meter.
                if let from = source["stat_energy_from"]?.stringValue { imports.append(from) }
                if let to = source["stat_energy_to"]?.stringValue { exports.append(to) }
            case "solar":
                if let from = source["stat_energy_from"]?.stringValue { solar.append(from) }
            default:
                break
            }
        }
        gridImports = imports
        gridExports = exports
        self.solar = solar
        devices = (json["device_consumption"]?.arrayValue ?? []).compactMap { item in
            item["stat_consumption"]?.stringValue.map { Device(statistic: $0, name: item["name"]?.stringValue) }
        }
    }

    public var isEmpty: Bool { gridImports.isEmpty && solar.isEmpty && devices.isEmpty }
}
