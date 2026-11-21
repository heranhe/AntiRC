# AntiRC 1.0.0 (13) TestFlight 发布记录

日期：2026-10-05（Asia/Shanghai）。

## 修复与依据

实体 iPhone 安装构建 11。只读检查 App 偏好发现：活跃记录保存 Google `AccountChooser` 登录中转入口，其 `continue` 指向官方远程实例；账户标签存在，账户编号及全局编号均为空。原代码校验历史原始 URL 是否属于远程页面，导致此入口的账户编号无法保存。

构建 13 解包官方登录中转地址并迁移旧历史记录；账户菜单 iframe 中的主动选择立即持久化，继续打开原实例及会话；默认页面回退不会覆盖选择；恢复重试最多一次；点击账户头像后提示跨导航保持关闭。设置显示真实版本并提供本机脱敏诊断。

完整证据：[GoogleAccountInvestigation.md](GoogleAccountInvestigation.md)。

## 验证

1. 原生 `AccountRecoveryTests`：14 项通过。
2. JavaScript：23 项通过。
3. 两次独立 `test-without-building` 进程：写入、恢复各 1 项通过。写入过程使用旧 AccountChooser 入口，并模拟默认账户页面回退。
4. Release 归档、签名及 App Store Connect 导出成功。
5. 实体 iPhone 的真实 Google 页面杀进程重开验收尚未完成；设备交互服务拒绝选择实体设备，CLI 已完成版本及偏好数据核对。不会把模拟器或偏好检查表述为最终真机页面验收。

## Apple 确认的发布状态

- App ID：`6814856474`
- Bundle ID：`com.heran.antigravity.remote`
- 版本：`1.0.0 (13)`
- Build ID：`968ef248-428a-4f66-a22d-67f47792e702`
- Processing：`VALID`
- Internal：`IN_BETA_TESTING`
- External：`IN_BETA_TESTING`
- Beta Review：`APPROVED`
- 内部组已有所有构建访问权限；外部测试组已关联本构建。
- 中文及英文 What to Test 已创建并读回，换行已保留。
- [TestFlight 测试入口](https://testflight.apple.com/join/wbDWtfqF)

IPA：`/tmp/antirc-testflight-13/AntigravityRemote.ipa`

SHA-256：`d94995a817a9f3a167bac869e75a146a9e6ab8aed80ac06dce245094c6f02f8b`

## 用户验收步骤

升级到构建 13 后，先通过右上角头像选择一次与电脑相同的账户，让新版本建立旧记录缺失的账户编号；然后完全关闭 App、重开并连接，检查最终头像和远程实例归属。重复开关应保持该选择。主动切回默认账户也应正常保存。

若仍发生回退，可从设置 → 连接诊断复制本机脱敏记录，定位首次请求及最终跳转差异。App 不会自动上传日志。
