import CryptoKit
import Foundation

/// Pure AWS Signature Version 4 signer (header-based auth). No I/O: callers
/// pass the request parts and a date, which makes the output unit-testable
/// against AWS's published known-answer vectors.
struct S3SigV4Signer: Sendable {
    var accessKeyID: String
    var secretAccessKey: String
    var region: String
    var sessionToken: String?
    var service: String

    init(accessKeyID: String, secretAccessKey: String, region: String, sessionToken: String? = nil, service: String = "s3") {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.region = region
        self.sessionToken = sessionToken
        self.service = service
    }

    struct SignedRequest: Sendable {
        var headers: [String: String]
    }

    static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    static let unsignedPayloadHash = "UNSIGNED-PAYLOAD"

    func sign(
        method: String,
        canonicalURI: String,
        canonicalQuery: String = "",
        host: String,
        extraHeaders: [String: String] = [:],
        payloadHash: String,
        date: Date
    ) -> SignedRequest {
        let amzDate = Self.amzDateString(from: date)
        let dateStamp = String(amzDate.prefix(8))

        let (headers, canonicalHeaders, signedHeaders) = canonicalHeaders(
            host: host,
            extraHeaders: extraHeaders,
            payloadHash: payloadHash,
            amzDate: amzDate
        )
        let canonicalRequest = Self.canonicalRequestBody(
            method: method,
            canonicalURI: canonicalURI,
            canonicalQuery: canonicalQuery,
            canonicalHeaders: canonicalHeaders,
            signedHeaders: signedHeaders,
            payloadHash: payloadHash
        )
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            Self.sha256Hex(canonicalRequest),
        ].joined(separator: "\n")

        let signingKey = Self.derivedSigningKey(
            secretAccessKey: secretAccessKey,
            dateStamp: dateStamp,
            region: region,
            service: service
        )
        let signature = Self.hex(
            HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: signingKey))
        )
        var signed = headers
        signed["Authorization"] = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return SignedRequest(headers: signed)
    }

    func canonicalRequest(
        method: String,
        canonicalURI: String,
        canonicalQuery: String,
        host: String,
        extraHeaders: [String: String],
        payloadHash: String,
        amzDate: String
    ) -> String {
        let (_, canonicalHeaders, signedHeaders) = canonicalHeaders(
            host: host,
            extraHeaders: extraHeaders,
            payloadHash: payloadHash,
            amzDate: amzDate
        )
        return Self.canonicalRequestBody(
            method: method,
            canonicalURI: canonicalURI,
            canonicalQuery: canonicalQuery,
            canonicalHeaders: canonicalHeaders,
            signedHeaders: signedHeaders,
            payloadHash: payloadHash
        )
    }

    private static func canonicalRequestBody(
        method: String,
        canonicalURI: String,
        canonicalQuery: String,
        canonicalHeaders: String,
        signedHeaders: String,
        payloadHash: String
    ) -> String {
        [
            method.uppercased(),
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")
    }

    private func canonicalHeaders(
        host: String,
        extraHeaders: [String: String],
        payloadHash: String,
        amzDate: String
    ) -> (headers: [String: String], canonicalHeaders: String, signedHeaders: String) {
        var headers = [String: String]()
        for (key, value) in extraHeaders {
            headers[key.lowercased()] = value
        }
        headers["host"] = host
        headers["x-amz-content-sha256"] = payloadHash
        headers["x-amz-date"] = amzDate
        if let sessionToken, !sessionToken.isEmpty {
            headers["x-amz-security-token"] = sessionToken
        }
        let keys = headers.keys.sorted()
        let canonical = keys.map { "\($0):\(headers[$0]!.trimmingCharacters(in: .whitespaces))\n" }.joined()
        return (headers, canonical, keys.joined(separator: ";"))
    }

    private static let amzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    static func amzDateString(from date: Date) -> String {
        amzDateFormatter.string(from: date)
    }

    static func sha256Hex(_ string: String) -> String {
        hex(SHA256.hash(data: Data(string.utf8)))
    }

    static func derivedSigningKey(secretAccessKey: String, dateStamp: String, region: String, service: String) -> Data {
        let kDate = hmac(key: Data("AWS4\(secretAccessKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmac(key: kDate, data: Data(region.utf8))
        let kService = hmac(key: kRegion, data: Data(service.utf8))
        return hmac(key: kService, data: Data("aws4_request".utf8))
    }

    private static func hmac(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// RFC 3986 encoding as required by SigV4: only the unreserved set
/// (A-Z, a-z, 0-9, `-`, `_`, `.`, `~`) stays literal.
func s3URIEncode(_ string: String, encodeSlash: Bool) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    if !encodeSlash {
        allowed.insert(charactersIn: "/")
    }
    return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
}
