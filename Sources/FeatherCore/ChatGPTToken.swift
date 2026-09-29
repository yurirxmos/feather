import CryptoKit
import Foundation

public enum ChatGPTToken {
    public static func randomString(length: Int) -> String {
        Data((0..<length).map { _ in UInt8.random(in: 0...255) }).map { String(format: "%02x", $0) }.joined()
    }

    public static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func formData(_ values: [String: String]) -> Data {
        values.sorted(by: { $0.key < $1.key })
            .map { "\(formComponent($0.key))=\(formComponent($0.value))" }
            .joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private static func formComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        return (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
            .replacingOccurrences(of: "%20", with: "+")
    }

    public static func base64URL<D: DataProtocol>(_ data: D) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func accountID(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let data = Data(base64Encoded: String(parts[1]) + String(repeating: "=", count: (4 - parts[1].count % 4) % 4), options: .ignoreUnknownCharacters),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let id = json["chatgpt_account_id"] as? String { return id }
        if let auth = json["https://api.openai.com/auth"] as? [String: Any], let id = auth["chatgpt_account_id"] as? String { return id }
        return (json["organizations"] as? [[String: Any]])?.first?["id"] as? String
    }
}
