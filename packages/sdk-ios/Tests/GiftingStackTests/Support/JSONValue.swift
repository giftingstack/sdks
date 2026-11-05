import Foundation
import XCTest

/// Untyped JSON for the fixtures. Numbers are Doubles (every fixture integer is exact in a
/// Double). Bool and number stay apart: JSONDecoder never decodes a JSON number as Bool.
enum JSONValue: Equatable, Codable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:
            try c.encodeNil()
        case .bool(let b):
            try c.encode(b)
        case .number(let n):
            // Integers as integers, so a model decoding `Int` never sees "1000.0".
            if n.rounded() == n && abs(n) < 1e15 {
                try c.encode(Int64(n))
            } else {
                try c.encode(n)
            }
        case .string(let s):
            try c.encode(s)
        case .array(let a):
            try c.encode(a)
        case .object(let o):
            try c.encode(o)
        }
    }

    // MARK: Access

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self {
            return o[key]
        }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self {
            return o
        }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self {
            return a
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self {
            return s
        }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let n) = self {
            return n
        }
        return nil
    }

    var intValue: Int? {
        if case .number(let n) = self, n.rounded() == n {
            return Int(n)
        }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let b) = self {
            return b
        }
        return nil
    }

    var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    /// A string, or nil for JSON null / a missing key.
    static func optionalString(_ value: JSONValue?) -> String? {
        value?.stringValue
    }

    // MARK: Conversion

    static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// The wire JSON of any Encodable value.
    static func of<T: Encodable>(_ value: T) throws -> JSONValue {
        try parse(JSONEncoder().encode(value))
    }

    /// Decodes a model from fixture JSON.
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }

    func data() throws -> Data {
        try JSONEncoder().encode(self)
    }

    // MARK: Printing

    var description: String {
        switch self {
        case .null:
            return "null"
        case .bool(let b):
            return b ? "true" : "false"
        case .number(let n):
            if n.rounded() == n && abs(n) < 1e15 {
                return String(Int64(n))
            }
            return String(n)
        case .string(let s):
            return "\"\(s)\""
        case .array(let a):
            return "[" + a.map { $0.description }.joined(separator: ",") + "]"
        case .object(let o):
            let parts = o.keys.sorted().map { key in "\"\(key)\":\(o[key]!.description)" }
            return "{" + parts.joined(separator: ",") + "}"
        }
    }
}

/// Every difference between two JSON values, as "path: expected X, got Y" lines.
func jsonDifferences(expected: JSONValue, actual: JSONValue, path: String = "$") -> [String] {
    switch (expected, actual) {
    case (.object(let e), .object(let a)):
        var out: [String] = []
        for key in Set(e.keys).union(a.keys).sorted() {
            let at = "\(path).\(key)"
            switch (e[key], a[key]) {
            case (let ev?, let av?):
                out += jsonDifferences(expected: ev, actual: av, path: at)
            case (let ev?, nil):
                out.append("\(at): expected \(ev), key missing")
            case (nil, let av?):
                out.append("\(at): unexpected key with \(av)")
            case (nil, nil):
                break
            }
        }
        return out
    case (.array(let e), .array(let a)):
        if e.count != a.count {
            return ["\(path): expected \(expected), got \(actual)"]
        }
        var out: [String] = []
        for i in 0..<e.count {
            out += jsonDifferences(expected: e[i], actual: a[i], path: "\(path)[\(i)]")
        }
        return out
    default:
        return expected == actual ? [] : ["\(path): expected \(expected), got \(actual)"]
    }
}

/// Fails with every difference, prefixed with where it happened.
func assertJSONEqual(
    _ actual: JSONValue,
    _ expected: JSONValue,
    _ context: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for difference in jsonDifferences(expected: expected, actual: actual) {
        XCTFail("\(context): \(difference)", file: file, line: line)
    }
}

struct FixtureError: Error, CustomStringConvertible {
    let description: String
}

/// The shared contract files, found relative to this source file.
enum Fixtures {
    /// packages/sdk-spec, from packages/sdk-ios/Tests/GiftingStackTests/Support/JSONValue.swift.
    static var specDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // GiftingStackTests
            .appendingPathComponent("../../../sdk-spec")
            .standardizedFileURL
    }

    static func load(_ relativePath: String) throws -> JSONValue {
        let url = specDirectory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureError(description: "fixture file missing: \(url.path) (the tests read packages/sdk-spec from the repository)")
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONValue.parse(data)
        } catch {
            throw FixtureError(description: "fixture file is not valid JSON: \(url.path): \(error)")
        }
    }

    /// `conformance/<name>`.
    static func conformance(_ name: String) throws -> JSONValue {
        try load("conformance/\(name)")
    }

    /// A non-empty array, or a thrown error naming it.
    static func list(_ value: JSONValue?, _ what: String) throws -> [JSONValue] {
        guard let items = value?.arrayValue, !items.isEmpty else {
            throw FixtureError(description: "\(what) is missing or empty")
        }
        return items
    }
}
