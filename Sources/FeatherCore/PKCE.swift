import CryptoKit
import Foundation

/// PKCE helpers for the Feather Plus browser sign-in.
public enum PKCE {
    public static func randomString(length: Int) -> String {
        Data((0..<length).map { _ in UInt8.random(in: 0...255) }).map { String(format: "%02x", $0) }.joined()
    }

    public static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func base64URL<D: DataProtocol>(_ data: D) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
