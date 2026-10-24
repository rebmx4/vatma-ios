import Foundation
import Security
import CryptoKit

enum SiteTrust {
    static func evaluate(_ trust: SecTrust) -> Bool {
        if SecTrustEvaluateWithError(trust, nil) { return true }
        let anchors = pinnedRoots()
        guard !anchors.isEmpty,
              SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, false) == errSecSuccess else { return false }
        // The challenge's original SSL/hostname policy remains attached to this trust.
        return SecTrustEvaluateWithError(trust, nil)
    }

    private static func pinnedRoots() -> [SecCertificate] {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("certificates", isDirectory: true),
              let manifest = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let document = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let rows = document["certificates"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard row["type"] as? String == "root", let file = row["file"] as? String,
                  file == (file as NSString).lastPathComponent, !file.contains("\\"),
                  let expected = row["sha256"] as? String,
                  let fingerprint = row["fingerprint256"] as? String,
                  let pem = try? Data(contentsOf: folder.appendingPathComponent(file)),
                  digest(pem) == expected.lowercased(), let text = String(data: pem, encoding: .utf8) else { return nil }
            let body = text.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
                .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
                .filter { !$0.isWhitespace }
            guard let der = Data(base64Encoded: body), digest(der) == fingerprint.replacingOccurrences(of: ":", with: "").lowercased(),
                  let cert = SecCertificateCreateWithData(nil, der as CFData),
                  let key = SecCertificateCopyKey(cert),
                  let attributes = SecKeyCopyAttributes(key) as? [String: Any],
                  attributes[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeRSA as String else { return nil }
            return cert
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
