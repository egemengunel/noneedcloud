import Foundation

struct CloudHTTPRequest: Sendable {
    var method: String
    var url: URL
    var headers: [String: String]
    var bodyFileURL: URL?
    var bodyData: Data?

    init(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        bodyFileURL: URL? = nil,
        bodyData: Data? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.bodyFileURL = bodyFileURL
        self.bodyData = bodyData
    }
}

struct CloudHTTPResponse: Sendable {
    var status: Int
    var data: Data

    var isSuccess: Bool { (200..<300).contains(status) }

    var bodySnippet: String {
        let text = String(data: data.prefix(200), encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ")
        return text.map { "Response: \($0)" } ?? "Response: \(data.count) bytes."
    }
}

/// The single HTTP seam every cloud destination goes through, so handlers
/// and run flows can be tested against fakes with no network.
protocol HTTPClient: AnyObject, Sendable {
    func send(_ request: CloudHTTPRequest) async throws -> CloudHTTPResponse
}

final class URLSessionHTTPClient: HTTPClient {
    init() {}

    func send(_ request: CloudHTTPRequest) async throws -> CloudHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.allHTTPHeaderFields = request.headers
        let data: Data
        let response: URLResponse
        if let bodyFileURL = request.bodyFileURL {
            (data, response) = try await URLSession.shared.upload(for: urlRequest, fromFile: bodyFileURL)
        } else {
            urlRequest.httpBody = request.bodyData
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        }
        return CloudHTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }
}
