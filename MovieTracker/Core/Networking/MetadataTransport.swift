import Foundation

struct MetadataHTTPResponse: Sendable {
    let data: Data
    let status: Int
    let retryAfter: String?
}

protocol MetadataTransport: Sendable {
    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse
}

/// No persistent response cache, redirects, retry loop, or credential logging.
final class URLSessionMetadataTransport: MetadataTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MetadataError.invalidResponse }
        return MetadataHTTPResponse(
            data: data, status: http.statusCode,
            retryAfter: http.value(forHTTPHeaderField: "Retry-After")
        )
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            // Never forward authorization to an unexpected redirect destination.
            completionHandler(nil)
        }
    }
}
