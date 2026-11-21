const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
test('Swift routing retains numeric paths and restores the Antigravity session index', () => {
  const source = fs.readFileSync(path.join(__dirname, '../AntigravityRemote/Utils/UserAgentHelper.swift'), 'utf8');
  const local = source.slice(source.indexOf('    public static func isLocalNetworkAddress'), source.indexOf('    /// 校验是否为有效的 URL 格式'));
  const methods = source.slice(source.indexOf('    public static func extractEmail'), source.indexOf('\n/// Google 账号登录识别'));
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'antirc-account-test-'));
  try {
    const file = path.join(dir, 'main.swift');
    fs.writeFileSync(file, 'import Foundation\npublic enum UserAgentHelper {\n' + local + methods + `
assert(UserAgentHelper.isLocalNetworkAddress("192.168.1.8:3000"))
assert(UserAgentHelper.isLocalNetworkAddress("http://172.20.0.2"))
assert(UserAgentHelper.isLocalNetworkAddress("mac-mini.local:8080"))
assert(!UserAgentHelper.isLocalNetworkAddress("antigravity.google.com/r/abc10.def"))
assert(!UserAgentHelper.isLocalNetworkAddress("172.32.0.1"))
assert(!UserAgentHelper.isLocalNetworkAddress("example.com/v10.2"))
let host = "antigravity.google.com"
assert(UserAgentHelper.shouldOpenInApp(URL(string: "https://accounts.google.com/AddSession")!, connectionHost: host))
assert(UserAgentHelper.shouldOpenInApp(URL(string: "https://ogs.google.com/u/0/widget/account")!, connectionHost: host))
assert(!UserAgentHelper.shouldOpenInApp(URL(string: "https://github.com/google/antigravity")!, connectionHost: host))
assert(!UserAgentHelper.shouldOpenInApp(URL(string: "https://google.com.evil.test/")!, connectionHost: host))
assert(!UserAgentHelper.shouldOpenInApp(URL(string: "mailto:someone@example.com")!, connectionHost: host))
assert(UserAgentHelper.shouldOpenInApp(URL(string: "http://192.168.1.8:3000/x")!, connectionHost: "192.168.1.8"))
let remote = URL(string: "https://antigravity.google.com/r/device?p=c%2Fthread#chat")!
let resumed = AntigravityAccountRoute.applying("2", to: remote)
assert(resumed.path == "/u/2/r/device")
assert(AntigravityAccountRoute.sessionIndex(in: resumed) == "2")
assert(AntigravityAccountRoute.sessionIndex(in: remote) == nil)
assert(AntigravityAccountRoute.connectionKey(for: resumed) == AntigravityAccountRoute.connectionKey(for: remote))
assert(AntigravityAccountRoute.applying("person@example.com", to: remote) == remote)
assert(AntigravityAccountRoute.applying("0", to: resumed).path == "/u/0/r/device")
let old = URL(string: "https://antigravity.google.com/u/old@example.com/r/device?authuser=old@example.com")!
assert(AntigravityAccountRoute.applying("3", to: old).absoluteString == "https://antigravity.google.com/u/3/r/device")
assert(AntigravityAccountRoute.sessionIndex(in: URL(string: "https://antigravity.google.com/u/2/oauth/start")!) == nil)
assert(AntigravityAccountRoute.sessionIndex(in: URL(string: "https://accounts.google.com/u/2/")!) == nil)
let unscoped = AntigravityAccountRoute.removingSessionIndex(from: URL(string: "https://antigravity.google.com/u/2/r/device?authuser=2&p=c%2Fthread#chat")!)
assert(unscoped.path == "/r/device")
assert(URLComponents(url: unscoped, resolvingAgainstBaseURL: false)!.queryItems!.map(\\.name) == ["p"])
assert(unscoped.fragment == "chat")
print("Account URL assertions passed")
`);
    const result = spawnSync('swift', ['-module-cache-path', path.join(dir, 'cache'), file], {encoding: 'utf8', timeout: 60000});
    assert.equal(result.status, 0, result.stdout + result.stderr);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});
