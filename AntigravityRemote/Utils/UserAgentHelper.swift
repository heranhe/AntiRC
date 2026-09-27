//
//  UserAgentHelper.swift
//  AntigravityRemote
//
//  URL 与 User-Agent 兼容性处理工具
//

import Foundation
import UIKit

public enum UserAgentHelper {
    /// 格式化与补全用户输入的 URL
    /// 如果用户只输入了 IP:Port 或域名，自动补全协议头
    public static func sanitizeURLString(_ input: String) -> String {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        // 如果没有协议前缀
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            // 如果包含 localhost、127.0.0.1 或局域网私网 IP，默认使用 http://
            if isLocalNetworkAddress(trimmed) {
                trimmed = "http://" + trimmed
            } else {
                trimmed = "https://" + trimmed
            }
        }
        
        return trimmed
    }
    
    /// 判断是否是本地或局域网开发地址
    public static func isLocalNetworkAddress(_ input: String) -> Bool {
        let lower = input.lowercased()
        return lower.contains("localhost") ||
               lower.contains("127.0.0.1") ||
               lower.contains("192.168.") ||
               lower.contains("10.") ||
               lower.contains("172.")
    }
    
    /// 校验是否为有效的 URL 格式
    public static func isValidURL(_ input: String) -> Bool {
        let sanitized = sanitizeURLString(input)
        guard let url = URL(string: sanitized),
              let scheme = url.scheme,
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return false
        }
        return true
    }

    /// 与当前系统版本一致的 Mobile Safari UA。写死旧版本会让 Google 把内嵌页当成异常客户端。
    public static func mobileSafariUserAgent() -> String {
        let parts = UIDevice.current.systemVersion.split(separator: ".")
        let major = parts.first.map(String.init) ?? "17"
        let minor = parts.dropFirst().first.map(String.init) ?? "0"
        let osToken = "\(major)_\(minor)"
        let versionToken = "\(major).\(minor)"
        if UIDevice.current.userInterfaceIdiom == .pad {
            return "Mozilla/5.0 (iPad; CPU OS \(osToken) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(versionToken) Mobile/15E148 Safari/604.1"
        }
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(osToken) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(versionToken) Mobile/15E148 Safari/604.1"
    }

    /// 远程控制地址归一化（扫码 / 粘贴 / 手动输入统一入口）
    public static func normalizeRemoteURL(_ input: String) -> String {
        sanitizeURLString(input)
    }

    /// 远程控制地址合法性校验（阻止 javascript: 等危险 scheme）
    public static func isValidRemoteURL(_ input: String) -> Bool {
        let sanitized = sanitizeURLString(input)
        guard !sanitized.isEmpty,
              let url = URL(string: sanitized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return false
        }
        return true
    }
}

/// Google 账号登录识别。内嵌 WKWebView 无法完成它的蓝牙近距离验证。
public enum GoogleSignInGate {
    public static func isAccountLogin(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "accounts.google.com" || host == "accounts.youtube.com" {
            return true
        }
        let path = url.path.lowercased()
        return (host == "google.com" || host.hasSuffix(".google.com"))
            && (path.contains("/o/oauth2") || path.contains("/signin"))
    }

    /// 在 Google 登录页加载前执行：去掉内嵌网页特征，并避开无法完成的蓝牙通行密钥流程。
    public static let compatibilityScript = """
    (function () {
      var host = (location.hostname || '').toLowerCase();
      var isGoogleAccount = host === 'accounts.google.com' || host === 'accounts.youtube.com';
      if (!isGoogleAccount) return;

      try {
        if (window.webkit) {
          Object.defineProperty(window.webkit, 'messageHandlers', {
            configurable: true,
            get: function () { return undefined; }
          });
        }
      } catch (e) {}

      try {
        if (window.PublicKeyCredential) {
          window.PublicKeyCredential.isConditionalMediationAvailable = function () {
            return Promise.resolve(false);
          };
        }
      } catch (e) {}

      try {
        var credentials = navigator.credentials;
        if (credentials && credentials.get) {
          var originalGet = credentials.get.bind(credentials);
          credentials.get = function (options) {
            try {
              if (options && options.publicKey) {
                var pk = options.publicKey;
                if (pk.extensions) {
                  delete pk.extensions.cableRegistration;
                  delete pk.extensions.cableAuthentication;
                  delete pk.extensions.cable;
                }
                if (pk.allowCredentials && pk.allowCredentials.length) {
                  pk.allowCredentials = pk.allowCredentials.filter(function (cred) {
                    if (!cred.transports || !cred.transports.length) return true;
                    return cred.transports.some(function (transport) {
                      return transport !== 'hybrid' && transport !== 'cable' && transport !== 'ble';
                    });
                  });
                  if (!pk.allowCredentials.length) {
                    return Promise.reject(new DOMException('Hybrid transport is unavailable.', 'NotAllowedError'));
                  }
                }
              }
            } catch (e) {}
            return originalGet(options);
          };
        }
      } catch (e) {}

      var recovered = false;
      function recoverBluetoothPage() {
        if (recovered || !document.body) return;
        var text = document.body.innerText || '';
        if (text.indexOf('蓝牙') === -1 && text.toLowerCase().indexOf('bluetooth') === -1) return;
        var labels = ['试其他方式', '试试其他方式', 'Try another way', 'Try a different way'];
        var nodes = document.querySelectorAll('button, a, [role="link"], [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          var label = (nodes[i].innerText || '').replace(/\\s+/g, ' ').trim();
          for (var j = 0; j < labels.length; j++) {
            if (label === labels[j]) {
              recovered = true;
              nodes[i].click();
              return;
            }
          }
        }
      }
      function watch() {
        recoverBluetoothPage();
        if (!document.body) return;
        var observer = new MutationObserver(recoverBluetoothPage);
        observer.observe(document.body, { childList: true, subtree: true, characterData: true });
      }
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', watch);
      } else {
        watch();
      }
    })();
    """
}
