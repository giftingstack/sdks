import Foundation
import XCTest
@testable import GiftingStack

/// conformance/client.json: every scenario against a scripted transport and token provider.
final class ClientConformanceTests: XCTestCase {
    func testEveryClientScenario() async throws {
        let f = try Fixtures.conformance("client.json")
        let scenarios = try Fixtures.list(f["scenarios"], "client.json scenarios")
        for s in scenarios {
            try await runClientScenario(s, fixture: "client.json")
        }
    }

    // MARK: - Small unit checks

    func testEncodeURIComponentMatchesJavaScript() {
        XCTAssertEqual(encodeURIComponent("a/b c:d"), "a%2Fb%20c%3Ad")
        XCTAssertEqual(encodeURIComponent("ü-_.!~*'()"), "%C3%BC-_.!~*'()")
        XCTAssertEqual(encodeURIComponent("a+b&c=d?e#f"), "a%2Bb%26c%3Dd%3Fe%23f")
        XCTAssertEqual(encodeURIComponent("😀"), "%F0%9F%98%80")
        XCTAssertEqual(encodeURIComponent("AZaz09"), "AZaz09")
    }

    func testSaysWhereItRunsWithThePlatformAndOsHeaders() async throws {
        final class Recorder: GiftingTransport, @unchecked Sendable {
            private let lock = NSLock()
            private var seen: [[String: String]] = []
            var last: [String: String] {
                lock.lock()
                defer { lock.unlock() }
                return seen.last ?? [:]
            }

            func send(_ request: HTTPRequest) async throws -> HTTPResponse {
                lock.lock()
                seen.append(request.headers)
                lock.unlock()
                return HTTPResponse(status: 200, body: Data("{\"data\": []}".utf8))
            }
        }
        let recorder = Recorder()
        let client = GiftingClient(getToken: { _ in "t" }, transport: recorder)
        _ = try await client.getGifts()
        XCTAssertEqual(recorder.last["X-GiftingStack-Platform"], "ios")
        XCTAssertEqual(recorder.last["X-GiftingStack-OS"], "ios")
        let other = GiftingClient(getToken: { _ in "t" }, transport: recorder, platform: "web", os: nil)
        _ = try await other.getGifts()
        XCTAssertEqual(recorder.last["X-GiftingStack-Platform"], "web")
        XCTAssertNil(recorder.last["X-GiftingStack-OS"])
    }

    func testGeneratedIdempotencyKeysAreUUIDLike() {
        let a = newIdempotencyKey()
        let b = newIdempotencyKey()
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(ScriptedHTTP.isUUIDLike(a), a)
    }
}

/// The scripted transport and token provider of one scenario. Requests can arrive on any
/// thread, so the state is behind a lock.
final class ScriptedHTTP: GiftingTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let exchanges: [JSONValue]
    private let tokens: [JSONValue]
    private var requests = 0
    private var tokenCalls = 0
    private var sentHeaders: [[String: String]] = []
    private var recordedProblems: [String] = []

    init(exchanges: [JSONValue], tokens: [JSONValue]) {
        self.exchanges = exchanges
        self.tokens = tokens
    }

    var problems: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedProblems
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    var tokenCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return tokenCalls
    }

    private func problem(_ text: String) {
        lock.lock()
        recordedProblems.append(text)
        lock.unlock()
    }

    func nextToken(_ forceRefresh: Bool) throws -> String {
        lock.lock()
        let index = tokenCalls
        tokenCalls += 1
        lock.unlock()
        guard index < tokens.count else {
            problem("unexpected getToken call #\(index + 1)")
            throw FixtureError(description: "unexpected getToken call")
        }
        let token = tokens[index]
        if token["forceRefresh"]?.boolValue != forceRefresh {
            problem("getToken #\(index + 1) forceRefresh: expected \(String(describing: token["forceRefresh"])), got \(forceRefresh)")
        }
        return token["returns"]?.stringValue ?? ""
    }

    /// Counts the request and remembers its headers (lower-case names). Not async, so the lock
    /// is never held across a suspension.
    private func begin(_ request: HTTPRequest) -> (index: Int, headers: [String: String], seen: [[String: String]]) {
        lock.lock()
        defer { lock.unlock() }
        let index = requests
        requests += 1
        var headers: [String: String] = [:]
        for (key, value) in request.headers {
            headers[key.lowercased()] = value
        }
        sentHeaders.append(headers)
        return (index: index, headers: headers, seen: sentHeaders)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let started = begin(request)
        let index = started.index
        let headers = started.headers
        let seen = started.seen

        let at = "request \(index + 1)"
        guard index < exchanges.count else {
            problem("unexpected \(at): \(request.method) \(request.url)")
            throw FixtureError(description: "unexpected request")
        }
        let exchange = exchanges[index]
        let want = exchange["request"] ?? .null

        if request.method != want["method"]?.stringValue {
            problem("\(at) method: expected \(String(describing: want["method"])), got \(request.method)")
        }
        if request.url != want["url"]?.stringValue {
            problem("\(at) url: expected \(String(describing: want["url"])), got \(request.url)")
        }
        for (name, expected) in want["headers"]?.objectValue ?? [:] {
            let got = headers[name.lowercased()]
            let wanted = expected.stringValue ?? ""
            if wanted == "<any-uuid-like>" {
                if !ScriptedHTTP.isUUIDLike(got ?? "") {
                    problem("\(at) \(name): expected a uuid-like value, got \(String(describing: got))")
                }
            } else if let n = ScriptedHTTP.sameAsRequest(wanted) {
                let earlier = n >= 1 && n <= seen.count ? seen[n - 1][name.lowercased()] : nil
                if got == nil || got != earlier {
                    problem("\(at) \(name): expected the value of request \(n) (\(String(describing: earlier))), got \(String(describing: got))")
                }
            } else if got != wanted {
                problem("\(at) \(name): expected \(wanted), got \(String(describing: got))")
            }
        }
        for absent in want["absentHeaders"]?.arrayValue ?? [] {
            let name = absent.stringValue ?? ""
            if let got = headers[name.lowercased()] {
                problem("\(at) \(name) must be absent, got \(got)")
            }
        }
        let wantBody = want["body"] ?? .null
        if wantBody.isNull {
            if let body = request.body {
                problem("\(at) body: expected none, got \(String(decoding: body, as: UTF8.self))")
            }
        } else if let body = request.body {
            do {
                let parsed = try JSONValue.parse(body)
                for difference in jsonDifferences(expected: wantBody, actual: parsed) {
                    problem("\(at) body: \(difference)")
                }
            } catch {
                problem("\(at) body is not JSON: \(String(decoding: body, as: UTF8.self))")
            }
        } else {
            problem("\(at) body: expected \(wantBody), got none")
        }

        if exchange["networkError"]?.boolValue == true {
            throw URLError(.notConnectedToInternet)
        }
        let response = exchange["response"] ?? .null
        let status = response["status"]?.intValue ?? 0
        var responseHeaders: [String: String] = [:]
        for (key, value) in response["headers"]?.objectValue ?? [:] {
            responseHeaders[key] = value.stringValue ?? ""
        }
        let responseBody: Data
        if let text = response["bodyText"]?.stringValue {
            responseBody = Data(text.utf8)
        } else {
            responseBody = try (response["body"] ?? .null).data()
        }
        return HTTPResponse(status: status, headers: responseHeaders, body: responseBody)
    }

    /// `^[0-9A-Fa-f-]{16,255}$`
    static func isUUIDLike(_ value: String) -> Bool {
        guard value.count >= 16 && value.count <= 255 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "0"..."9", "a"..."f", "A"..."F", "-":
                return true
            default:
                return false
            }
        }
    }

    /// `<same-as-request:N>` gives N.
    static func sameAsRequest(_ value: String) -> Int? {
        let prefix = "<same-as-request:"
        guard value.hasPrefix(prefix), value.hasSuffix(">") else {
            return nil
        }
        let digits = value.dropFirst(prefix.count).dropLast()
        return Int(digits)
    }
}
