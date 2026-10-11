import XCTest
@testable import StreetlightMapper

// Shared helpers for tests that need an isolated store / stubbed network.

enum TestSupport {

    static func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("slm-tests-\(UUID().uuidString)", isDirectory: true)
    }

    static func makeSession(pole: String = "208125",
                            lights: [String] = ["E5000531"],
                            poleConfidence: Confidence = .high) -> CaptureSession {
        var s = CaptureSession(poleID: pole, poleConfidence: poleConfidence)
        for serial in lights {
            s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: serial, confidence: .high))
        }
        return s
    }

    /// A throwaway UserDefaults so tests never touch the app's real settings.
    static func isolatedDefaults() -> UserDefaults {
        let name = "slm-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// Runs the main run loop until `condition` is true or the timeout expires.
    static func wait(timeout: TimeInterval = 5, until condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }
}

/// Intercepts URLSession traffic so sync tests need no real network.
final class StubURLProtocol: URLProtocol {

    static var statusCode = 201
    static var failWithError = false
    static private(set) var requests: [URLRequest] = []
    static private(set) var bodies: [Data] = []

    static func reset() {
        statusCode = 201
        failWithError = false
        requests = []
        bodies = []
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            stream.close()
            Self.bodies.append(data)
        } else if let body = request.httpBody {
            Self.bodies.append(body)
        }

        if Self.failWithError {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        } else {
            let resp = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
