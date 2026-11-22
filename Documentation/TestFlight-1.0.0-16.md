# AntiRC 1.0.0 (16) TestFlight 发布记录

日期：2026-11-23（Asia/Shanghai）。基于 1.0.0 (15)。针对“登录后掉线、反复要求重新登录、登录要好几分钟”。

## 原因与修复

1. **User-Agent 与真实 Safari 不一致**：旧版自己拼接 UA，系统部分写成 `iPhone OS 26_1`；但 iOS 26 起 WebKit/Safari 会把系统版本冻结为 `iPhone OS 18_x`（模拟器实测为 `18_7`）。真实 Safari 不会发出这种组合，Google 可能把它当作异常客户端，导致更多验证、会话更短。现在系统部分交给 WebKit 生成，只追加 `Version/x.y Mobile/15E148 Safari/604.1`，与 Safari 一致。桌面版和自定义预设不变。
2. **登录完成后又被拉去登录**：之前只有“点击链接或提交表单”打开登录页才算用户主动登录。网页脚本自动跳转的登录页不算，所以登录完回到远程页面时，App 仍会做一次“纠正回旧账号编号”的重试；如果旧编号已不在本机登录账号中，Google 会再次要求登录。现在只要登录、选账号或验证页面真正展示过（CheckCookie、SetSID、RotateCookies 等自动中转除外），落地的账号就视为用户的选择，不再纠正。
3. **纠正重试不再引发登录**：自动纠正如果被 Google 带到登录页，说明该编号已失效，App 会放弃纠正、回到刚才的页面，并显示“账号未恢复”提示让用户选择，不再要求用户为一个不存在的编号重新登录。偏好不会被自动改写。
4. **页面内链接沿用当前页面所在账号**：不再强加保存的编号，避免账号未恢复时点任意链接都跳去登录。
5. **登录页卡顿**：
   - 对话桥脚本原本注入所有站点和 frame，在 Google 登录页上也每 0.1–0.7 秒扫描一次页面。现在跳过 `accounts.google.com`、`accounts.youtube.com`、`ogs.google.com`、`myaccount.google.com`。
   - 蓝牙验证检测原本在每次 DOM 变化时读取 `innerText`（强制重排），现在改为 `textContent`、300ms 节流，处理后断开观察。
6. 兼容脚本也注入 `accounts.google.com` 子 frame（Cookie 轮换等），同样隐藏内嵌特征。
7. 诊断记录区分 `google-login`（展示给用户的登录页）与 `google-passthrough`（自动中转），新增 `signInShown`、`recoveryAbandoned` 事件，便于下次定位。

## 验证

- 原生 `AccountRecoveryTests`：27 项通过。新增 6 项：登录后落地接受、自动中转仍恢复、纠正遇登录放弃、用户主动登录不被拦截、页面内链接沿用当前账号、WebKit 生成 Safari UA。
- 模拟器实测 WebKit 生成的 UA：`Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Mobile/15E148 Safari/604.1`。
- 模拟器冒烟：打开远程页面正常；点击 Sign in 到 Google 登录页加载完成约 4 秒，未出现“浏览器不安全”拦截；诊断记录到 `signInShown`。未输入任何账号。
- JavaScript：23 项通过。
- 未完成：真实 Google 账号的真机登录、杀进程重开、隔天保持登录验收。无法在本机验证 Google 服务端对会话时长的判断。

## 上传

- 版本：`1.0.0 (16)`，Release 归档，自动签名（团队 `G6JJHZL29U`）。
- `xcodebuild -exportArchive`（app-store-connect / upload）：Upload succeeded，构建处于 Apple 处理流程中。
- 外部测试组分配与 What to Test 需在 App Store Connect 中确认。
