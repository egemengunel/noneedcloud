import Foundation
import Testing
@testable import NoNeedCloudCore

/// Pins the signer to AWS's published reference vectors
/// (docs.aws.amazon.com/AmazonS3/latest/developerguide/sig-v4-header-based-auth.html).
struct S3SigV4Tests {
    // Example: GET Object — 2013-05-24T00:00:00Z, us-east-1, s3.
    private static let vectorDate = Date(timeIntervalSince1970: 1_369_353_600)
    private static let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    private func makeSigner(sessionToken: String? = nil) -> S3SigV4Signer {
        S3SigV4Signer(
            accessKeyID: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            sessionToken: sessionToken
        )
    }

    @Test func getVanillaKnownAnswerSignature() {
        let signed = makeSigner().sign(
            method: "GET",
            canonicalURI: "/test.txt",
            host: "examplebucket.s3.amazonaws.com",
            extraHeaders: ["Range": "bytes=0-9"],
            payloadHash: Self.emptyHash,
            date: Self.vectorDate
        )

        #expect(signed.headers["x-amz-date"] == "20130524T000000Z")
        #expect(signed.headers["x-amz-content-sha256"] == Self.emptyHash)
        #expect(
            signed.headers["Authorization"]
                == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, "
                + "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, "
                + "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
        )
    }

    @Test func canonicalRequestMatchesDocumentedGetVanilla() {
        let canonical = makeSigner().canonicalRequest(
            method: "GET",
            canonicalURI: "/test.txt",
            canonicalQuery: "",
            host: "examplebucket.s3.amazonaws.com",
            extraHeaders: ["Range": "bytes=0-9"],
            payloadHash: Self.emptyHash,
            amzDate: "20130524T000000Z"
        )
        let expected = [
            "GET",
            "/test.txt",
            "",
            "host:examplebucket.s3.amazonaws.com\nrange:bytes=0-9\nx-amz-content-sha256:\(Self.emptyHash)\nx-amz-date:20130524T000000Z\n",
            "host;range;x-amz-content-sha256;x-amz-date",
            Self.emptyHash,
        ].joined(separator: "\n")
        #expect(canonical == expected)
    }

    @Test func sessionTokenBecomesSignedSecurityTokenHeader() {
        let signed = makeSigner(sessionToken: "TOK").sign(
            method: "PUT",
            canonicalURI: "/bucket/key",
            host: "minio.local:9000",
            extraHeaders: [:],
            payloadHash: S3SigV4Signer.unsignedPayloadHash,
            date: Self.vectorDate
        )
        #expect(signed.headers["x-amz-security-token"] == "TOK")
        #expect(signed.headers["Authorization"]?.contains("x-amz-security-token") == true)
    }

    @Test func uriEncodingFollowsRFC3986UnreservedSet() {
        #expect(s3URIEncode("hello.txt", encodeSlash: false) == "hello.txt")
        #expect(s3URIEncode("a b/c+d.txt", encodeSlash: false) == "a%20b/c%2Bd.txt")
        #expect(s3URIEncode("a b/c+d.txt", encodeSlash: true) == "a%20b%2Fc%2Bd.txt")
        #expect(s3URIEncode("ä-ö_~.-", encodeSlash: false) == "%C3%A4-%C3%B6_~.-")
    }

    @Test func derivedSigningKeyIsDeterministicSixteenStepChain() {
        let key = S3SigV4Signer.derivedSigningKey(
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            dateStamp: "20130524",
            region: "us-east-1",
            service: "s3"
        )
        #expect(key.count == 32)
        #expect(
            key == S3SigV4Signer.derivedSigningKey(
                secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
                dateStamp: "20130524",
                region: "us-east-1",
                service: "s3"
            )
        )
        #expect(
            key != S3SigV4Signer.derivedSigningKey(
                secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
                dateStamp: "20130525",
                region: "us-east-1",
                service: "s3"
            )
        )
    }
}
