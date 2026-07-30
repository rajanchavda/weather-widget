import Foundation

final class URLProtocolMock: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var responseDelay: TimeInterval = 0
    nonisolated(unsafe) static var delayedURLs: [String] = []

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = URLProtocolMock.requestHandler else {
            let error = URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: "URLProtocolMock.requestHandler not set"])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let urlString = request.url?.absoluteString ?? ""

        do {
            let (response, data) = try handler(request)
            // Read delay after the handler so tests can configure it per-request.
            let shouldDelay = URLProtocolMock.delayedURLs.contains { urlString.contains($0) }
            let delay = shouldDelay ? URLProtocolMock.responseDelay : 0

            if delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                }
            } else {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            let shouldDelay = URLProtocolMock.delayedURLs.contains { urlString.contains($0) }
            let delay = shouldDelay ? URLProtocolMock.responseDelay : 0
            if delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    client?.urlProtocol(self, didFailWithError: error)
                }
            } else {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

extension URLSession {
    static var mock: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        return URLSession(configuration: config)
    }
}
