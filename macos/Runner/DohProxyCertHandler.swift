import Foundation
import Security

/// macOS 代理 CA 证书信任管理
///
/// macOS WKWebView 通过 CONNECT 代理时，TLS 验证在系统网络层完成，
/// 必须将 CA 添加到用户钥匙串才能让系统信任。
@objc class DohProxyCertHandler: NSObject {
    static let shared = DohProxyCertHandler()

    private var currentCertRef: SecCertificate?

    /// 加载 CA 证书并添加到钥匙串，返回是否信任成功
    func setCaCertPem(_ pem: String) -> Bool {
        let base64 = pem
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("-----")
            }
            .joined()
        guard let derData = Data(base64Encoded: base64),
              let certRef = SecCertificateCreateWithData(nil, derData as CFData) else {
            return false
        }
        currentCertRef = certRef
        return ensureTrusted(certRef)
    }

    /// 检查当前 CA 是否在钥匙串中被信任
    func isCaTrusted() -> Bool {
        guard let cert = currentCertRef else { return false }
        return checkTrusted(cert)
    }

    func clearCaCert() {
        currentCertRef = nil
    }

    // MARK: - Keychain

    /// 确保证书在钥匙串中且被信任，返回是否成功
    private func ensureTrusted(_ cert: SecCertificate) -> Bool {
        if checkTrusted(cert) { return true }
        return addAndTrust(cert)
    }

    /// 添加证书到钥匙串并设置信任
    private func addAndTrust(_ cert: SecCertificate) -> Bool {
        // 添加证书到默认钥匙串
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: "DOH Proxy CA",
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // 旧证书存在，替换
            SecItemDelete([
                kSecClass as String: kSecClassCertificate,
                kSecAttrLabel as String: "DOH Proxy CA",
            ] as CFDictionary)
            let retryStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if retryStatus != errSecSuccess {
                NSLog("[DohProxyCertHandler] Failed to replace CA: %d", retryStatus)
                return false
            }
        } else if addStatus != errSecSuccess {
            NSLog("[DohProxyCertHandler] Failed to add CA: %d", addStatus)
            return false
        }

        // 设置用户级信任
        let trustSettings: NSDictionary = [
            kSecTrustSettingsResult as String: NSNumber(value: SecTrustSettingsResult.trustRoot.rawValue),
        ]
        let trustStatus = SecTrustSettingsSetTrustSettings(cert, .user, [trustSettings] as CFArray)
        if trustStatus != errSecSuccess {
            NSLog("[DohProxyCertHandler] Failed to set trust: %d", trustStatus)
            return false
        }

        return true
    }

    /// 检查证书是否已在钥匙串中被信任
    private func checkTrusted(_ cert: SecCertificate) -> Bool {
        var trustSettings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(cert, .user, &trustSettings)
        guard status == errSecSuccess, let settings = trustSettings as? [[String: Any]] else {
            return false
        }
        return settings.contains { setting in
            (setting[kSecTrustSettingsResult as String] as? Int) == Int(SecTrustSettingsResult.trustRoot.rawValue)
        }
    }
}
