//
//  UserAgentHelper.swift
//  AntigravityRemote
//
//  URL 与 User-Agent 兼容性处理工具
//

import Foundation
import UIKit

/// Local, bounded navigation evidence. Never stores URLs, cookies, emails or token values.
final class AccountDiagnostics {
    static let shared = AccountDiagnostics()
    enum Event: String {
        case processStarted, settingsRestored, prepareInput, prepareTarget, routeSaved
        case loadRequested, navigationAction, popup, provisional, redirect, committed, finished
        case routeObserved, profileDetected, chooserOpened, provisionalFailed, navigationFailed
        case accountSelected, accountRecovery
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }

    private let defaults: UserDefaults
    private let key = "Antigravity_Account_Diagnostics_v1"
    private let lock = NSLock()
    private let processID = ProcessInfo.processInfo.processIdentifier

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        record(.processStarted)
    }

    static func safeIndex(_ value: String?) -> String {
        guard let value, !value.isEmpty, value.count <= 6,
              value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return "none" }
        return value
    }

    static func routeSummary(_ url: URL?) -> String {
        guard let url else { return "none" }
        let host = url.host?.lowercased() ?? ""
        let category: String
        switch host {
        case "antigravity.google.com": category = AntigravityAccountRoute.isRemotePage(url) ? "remote" : "remote-other"
        case "accounts.google.com": category = "google-login"
        case "ogs.google.com": category = "google-menu"
        default: category = "other"
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let authUser = query.first { $0.name == "authuser" }?.value
        return "\(category) pathIndex=\(safeIndex(AntigravityAccountRoute.sessionIndex(in: url))) authuser=\(safeIndex(authUser))"
    }

    private static let timestampFormatter = ISO8601DateFormatter()

    func record(_ event: Event, url: URL? = nil, selectedIndex: String? = nil, code: Int? = nil) {
        let line = "\(Self.timestampFormatter.string(from: Date())) pid=\(processID) app=\(Self.appVersion) \(event.rawValue) \(Self.routeSummary(url)) savedIndex=\(Self.safeIndex(selectedIndex))" + (code.map { " code=\($0)" } ?? "")
        lock.lock()
        defer { lock.unlock() }
        var lines = defaults.stringArray(forKey: key) ?? []
        lines.append(line)
        defaults.set(Array(lines.suffix(120)), forKey: key)
    }

    var report: String {
        lock.lock()
        defer { lock.unlock() }
        return (["AntiRC \(Self.appVersion) · local account navigation trace"] + (defaults.stringArray(forKey: key) ?? [])).joined(separator: "\n")
    }
}

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
    
    /// 判断是否是本地或局域网开发地址。只看主机名，避免路径里的 "10." 之类误判。
    public static func isLocalNetworkAddress(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let host = URLComponents(string: candidate)?.host else { return false }
        return isLocalNetworkHost(host)
    }

    /// localhost、回环地址、RFC 1918 私网地址与 .local 主机。
    public static func isLocalNetworkHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased()
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ $0 != nil && $0! >= 0 && $0! <= 255 }) else { return false }
        let a = octets[0]!, b = octets[1]!
        return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && (16...31).contains(b))
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
        let sanitized = sanitizeURLString(input)
        guard let url = URL(string: sanitized) else { return sanitized }
        return AntigravityAccountRoute.remoteDestination(in: url)?.absoluteString ?? sanitized
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

    /// 从任意字符串（如 Google 账号标题、姓名与邮箱混排文本）中精准提取 Email
    public static func extractEmail(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        if let match = regex.firstMatch(in: trimmed, options: [], range: range),
           let matchRange = Range(match.range, in: trimmed) {
            return String(trimmed[matchRange])
        }
        return nil
    }

    /// 应留在 App 内加载的主机：当前连接主机、Google 登录/账户相关站点。其余链接交给系统浏览器。
    public static func shouldOpenInApp(_ url: URL, connectionHost: String?) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        if scheme == "about" || scheme == "blob" || scheme == "data" { return true }
        guard scheme == "http" || scheme == "https", let host = url.host?.lowercased() else { return false }
        if let connectionHost, host == connectionHost.lowercased() { return true }
        if isLocalNetworkHost(host) { return true }
        if host == "accounts.youtube.com" { return true }
        let googleSuffixes = ["google.com", "googleusercontent.com", "gstatic.com", "googleapis.com"]
        return googleSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// Antigravity 的 ConfigService 从 /u/<数字>/ 读取 sessionIndex，缺省为 0。
/// 只保存和恢复这个编号，不复制网页的 OAuth token 或登录中转地址。
public enum AntigravityAccountRoute {
    /// Old histories may contain Google's AccountChooser URL instead of its continue target.
    /// Follow only known Google sign-in hosts and finish only at an official remote page.
    public static func remoteDestination(in url: URL) -> URL? {
        var candidate = url
        for _ in 0..<5 {
            if isRemotePage(candidate) { return candidate }
            guard candidate.scheme == "https",
                  ["accounts.google.com", "accounts.youtube.com"].contains(candidate.host?.lowercased() ?? ""),
                  let continuation = URLComponents(url: candidate, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "continue" })?.value,
                  let next = URL(string: continuation), next != candidate else { return nil }
            candidate = next
        }
        return nil
    }

    public static func isRemotePage(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host?.lowercased() == "antigravity.google.com" else { return false }
        let path = unscopedPath(url)
        return path == "/" || path.isEmpty || path == "/r" || path.hasPrefix("/r/")
    }

    public static func sessionIndex(in url: URL) -> String? {
        guard isRemotePage(url) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "u", validIndex(String(parts[1])) else { return nil }
        return String(parts[1])
    }

    /// Google menu links use authuser before the server canonicalizes them to /u/N/.
    public static func requestedSessionIndex(in url: URL) -> String? {
        guard isRemotePage(url) else { return nil }
        if let index = sessionIndex(in: url) { return index }
        guard let index = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "authuser" })?.value,
              validIndex(index) else { return nil }
        return index
    }

    public static func applying(_ index: String?, to url: URL) -> URL {
        guard isRemotePage(url), let index, validIndex(index),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        // 保留实例 ID、已编码的会话查询参数和 fragment。
        components.percentEncodedPath = "/u/\(index)" + unscopedPath(url)
        let items = components.queryItems?.filter { $0.name.lowercased() != "authuser" }
        components.queryItems = items?.isEmpty == true ? nil : items
        return components.url ?? url
    }

    /// 去掉 /u/N/ 与 authuser，得到由 Google 默认账号打开的同一实例地址。
    public static func removingSessionIndex(from url: URL) -> URL {
        guard isRemotePage(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.percentEncodedPath = unscopedPath(url)
        let items = components.queryItems?.filter { $0.name.lowercased() != "authuser" }
        components.queryItems = items?.isEmpty == true ? nil : items
        return components.url ?? url
    }

    public static func connectionKey(for url: URL) -> String {
        guard isRemotePage(url) else { return url.absoluteString }
        // 同一实例的根链接、账户链接及不同会话都复用同一条设备记录。
        return "https://antigravity.google.com" + unscopedPath(url)
    }

    private static func validIndex(_ index: String) -> Bool {
        !index.isEmpty && index.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    private static func unscopedPath(_ url: URL) -> String {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        // 同时修复旧版错误生成的 /u/<邮箱>/ 路径。
        let result = path.replacingOccurrences(of: #"^/u/[^/]+(?=/|$)"#, with: "", options: .regularExpression)
        return result.isEmpty ? "/" : result
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

/// 远程实例状态监测与断开提示汉化桥接
public enum InstanceStatusBridge {
    /// 注入到所有页面的断开状态检测与中文提示增强脚本
    public static let script = """
    (function () {
      if (window.__antigravityStatusBridgeInjected) return;
      if (location.hostname !== 'antigravity.google.com') return;
      window.__antigravityStatusBridgeInjected = true;

      // 只替换文本节点，不改写网页框架管理的元素结构。
      var replacements = [
        ['Instance disconnected', '远程实例未连接或已断开'],
        ['This instance is no longer connected', '请确认电脑端已登录同一个 Google 账号，并且 Antigravity 正在运行。'],
        ['Go to Instance Selector', '← 返回实例列表']
      ];
      var reported = false;
      var timer = null;

      function translateDisconnectedDialog() {
        timer = null;
        if (!document.body) return;
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        var found = false;
        var node;
        while ((node = walker.nextNode())) {
          var text = node.nodeValue;
          if (!text || text.length > 200) continue;
          for (var i = 0; i < replacements.length; i++) {
            if (text.indexOf(replacements[i][0]) === -1) continue;
            if (i === 0) found = true;
            node.nodeValue = replacements[i][1];
            break;
          }
        }
        if (found && !reported) {
          reported = true;
          try {
            window.webkit.messageHandlers.instanceStatus.postMessage({ status: 'disconnected', reason: 'instance_disconnected' });
          } catch (e) {}
        }
        if (!found && reported && document.body.innerText.indexOf('远程实例未连接或已断开') === -1) {
          // 单页应用内重新连上实例时，同步撤下原生提示。
          reported = false;
          try {
            window.webkit.messageHandlers.instanceStatus.postMessage({ status: 'connected' });
          } catch (e) {}
        }
      }

      function schedule() {
        // 流式输出时 DOM 变化频繁，合并为每 400ms 最多一次扫描。
        if (timer === null) timer = setTimeout(translateDisconnectedDialog, 400);
      }

      function initWatcher() {
        translateDisconnectedDialog();
        if (document.body) {
          new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
        }
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initWatcher);
      } else {
        initWatcher();
      }
    })();
    """
}

/// Observe the signed-in profile after hydration and in-page account switches.
/// Account chooser rows and page titles are not evidence of the active account.
enum GoogleAccountBridge {
    static let script = #"""
    (() => {
      if (!['antigravity.google.com', 'ogs.google.com'].includes(location.hostname)) return;
      // 捕获阶段先收起原生提示，不阻止 Google 自己打开账户菜单。
      const accountInteraction = event => {
        const target = event.target instanceof Element ? event.target : event.target?.parentElement;
        const control = target?.closest('a, button, [role="button"]');
        if (!control) return;
        const label = control.getAttribute('aria-label') || '';
        const href = control.getAttribute('href') || '';
        // Google's account menu lives in an ogs.google.com iframe and opens a new window.
        // Persist the actual selection before any popup/redirect, then let native WebKit
        // load the same instance/conversation under that account.
        if (event.type === 'click' && control.tagName === 'A' && href) {
          try {
            const destination = new URL(href, location.href);
            const index = destination.pathname.match(/^\/u\/(\d+)(?:\/|$)/)?.[1]
              || destination.searchParams.get('authuser');
            if (destination.protocol === 'https:' && destination.hostname === 'antigravity.google.com'
                && (destination.searchParams.has('authuser') || location.hostname === 'ogs.google.com')
                && /^(?:\/u\/\d+)?\/(?:r(?:\/[^?#]*)?)?$/.test(destination.pathname)
                && /^\d{1,6}$/.test(index || '')
                && window.webkit?.messageHandlers?.googleAccount) {
              event.preventDefault();
              event.stopImmediatePropagation();
              window.webkit.messageHandlers.googleAccount.postMessage({event: 'accountSelected', index});
              return;
            }
          } catch (_) {}
        }
        const isAccount = /Google\s*(Account|账号|帳號|账户)/i.test(label)
          || /^https:\/\/accounts\.google\.com\/SignOutOptions(?:[/?#]|$)/i.test(href)
          || (!!control.closest('#gb') && !!control.querySelector('img[src*="googleusercontent.com"]'));
        if (isAccount) window.webkit?.messageHandlers?.googleAccount?.postMessage({event: 'accountChooserOpened'});
      };
      document.addEventListener('pointerdown', accountInteraction, true);
      document.addEventListener('click', accountInteraction, true);
      let previous = '';
      const report = () => {
        const emails = new Set();
        for (const el of document.querySelectorAll('a[aria-label], button[aria-label], [role="button"][aria-label]')) {
          const label = el.getAttribute('aria-label') || '';
          if (!/Google\s*(Account|账号|帳號|账户)/i.test(label)) continue;
          if (!el.getClientRects().length || el.closest('[role="dialog"], [role="menu"], [role="listbox"]')) continue;
          const email = label.match(/[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}/)?.[0];
          if (email) emails.add(email);
        }
        if (emails.size !== 1) { previous = ''; return; }
        const email = [...emails][0];
        if (email !== previous) {
          previous = email;
          window.webkit.messageHandlers.googleAccount.postMessage(email);
        }
      };
      let timer;
      new MutationObserver(() => {
        clearTimeout(timer);
        timer = setTimeout(report, 100);
      }).observe(document.documentElement, {subtree: true, childList: true, attributes: true, characterData: true});
      report();
    })();
    """#
}
