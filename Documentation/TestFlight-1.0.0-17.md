# AntiRC 1.0.0 (17) TestFlight 发布记录

日期：2026-11-23（Asia/Shanghai）。基于 1.0.0 (16)。

## 改动

- **未登录时不再显示“已连接”**：欢迎页登录前后网址相同，过去只要不在 Google 登录页就判定为已连接。现在账号识别脚本在 Google 顶栏（`#gb`）出现 Sign in（`accounts.google.com/ServiceLogin`）链接且没有头像时报告 `signedOut`：
  - 顶部状态显示“等待登录 Google”，大厅记录显示连接中。
  - 新增 `pageSignedOut` 标记，页面加载完成和实例恢复连接时不会覆盖成已连接。
  - 同一页面内识别到头像（登录完成）或新文档提交时清除标记，恢复正常判断。

## 验证

- 原生 `AccountRecoveryTests`：28 项通过（新增未登录状态测试，覆盖“脚本先于 didFinish 报告”的时序）。
- JavaScript：24 项通过（新增：未登录只报告一次；已登录顶栏、顶栏外的登录链接、隐藏链接不报告）。
- 未完成：模拟器和真机上未实际走一遍未登录 → 登录的状态变化。

## 上传

- 版本：`1.0.0 (17)`，Release 归档，自动签名（团队 `G6JJHZL29U`）。
- `xcodebuild -exportArchive`（app-store-connect / upload）：Upload succeeded，构建处于 Apple 处理流程中。
- 外部测试组分配与 What to Test 需在 App Store Connect 中确认。
