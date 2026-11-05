#if canImport(SwiftUI) && canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import GiftingStack

/// Audit R-08: which URLs load, the byte cap, the decode bound and the 60 s failure memory.
final class StubImageProtocol: URLProtocol {
    static var hits = 0
    static var status = 200
    static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        StubImageProtocol.hits += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: StubImageProtocol.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(StubImageProtocol.body.count)]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubImageProtocol.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class GiftImageCacheTests: XCTestCase {
    private func png(width: Int, height: Int) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    private func makeCache() -> GiftImageCache {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubImageProtocol.self]
        StubImageProtocol.hits = 0
        StubImageProtocol.status = 200
        StubImageProtocol.body = Data()
        return GiftImageCache(session: URLSession(configuration: configuration))
    }

    private func loadAndWait(_ cache: GiftImageCache, _ url: String) async -> CGImage? {
        var result: CGImage?
        let done = expectation(description: "load \(url)")
        cache.load(url) { image in
            result = image
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
        return result
    }

    func testARefusedURLAnswersAtOnceAndSendsNoRequest() {
        let cache = makeCache()
        var called = false
        cache.load("http://assets.example.test/a.png") { image in
            called = true
            XCTAssertNil(image)
        }
        XCTAssertTrue(called, "a refused URL answers at once")
        XCTAssertEqual(StubImageProtocol.hits, 0, "and sends no request")
    }

    func testADataURLIsDecodedWithoutARequest() async {
        let cache = makeCache()
        let url = "data:image/png;base64," + png(width: 8, height: 8).base64EncodedString()
        let image = await loadAndWait(cache, url)
        XCTAssertEqual(image?.width, 8)
        XCTAssertEqual(StubImageProtocol.hits, 0)
        let broken = await loadAndWait(cache, "data:image/png;base64,@@@@")
        XCTAssertNil(broken)
    }

    func testABigPictureIsDecodedAsAThumbnail() {
        let wide = GiftImageCache.decode(png(width: 3000, height: 20))
        XCTAssertNotNil(wide)
        XCTAssertLessThanOrEqual(max(wide?.width ?? 0, wide?.height ?? 0), GiftImageLimits.maxPixelSize)
        let small = GiftImageCache.decode(png(width: 8, height: 8))
        XCTAssertEqual(small?.width, 8, "a small picture keeps its size")
        XCTAssertNil(GiftImageCache.decode(Data("not an image".utf8)))
    }

    func testTooBigADownloadIsAFailure() async {
        let cache = makeCache()
        StubImageProtocol.body = Data(count: GiftImageLimits.maxBytes + 1)
        let r1 = await loadAndWait(cache, "https://assets.test/huge.png")
        XCTAssertNil(r1)
        StubImageProtocol.body = png(width: 16, height: 16)
        let r2 = await loadAndWait(cache, "https://assets.test/ok.png")
        XCTAssertNotNil(r2)
    }

    func testAFailedPictureIsNotAskedForAgainForSixtySeconds() async {
        let cache = makeCache()
        var now: TimeInterval = 1_000
        cache.uptime = { now }
        StubImageProtocol.status = 404
        let r3 = await loadAndWait(cache, "https://assets.test/missing.png")
        XCTAssertNil(r3)
        XCTAssertEqual(StubImageProtocol.hits, 1)
        now += 59
        let r4 = await loadAndWait(cache, "https://assets.test/missing.png")
        XCTAssertNil(r4)
        XCTAssertEqual(StubImageProtocol.hits, 1, "remembered for 60 s")
        now += 2
        StubImageProtocol.status = 200
        StubImageProtocol.body = png(width: 16, height: 16)
        let r5 = await loadAndWait(cache, "https://assets.test/missing.png")
        XCTAssertNotNil(r5)
        XCTAssertEqual(StubImageProtocol.hits, 2, "asked again after the minute")
    }
}
#endif
