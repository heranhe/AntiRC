# 原生对话界面

连接后由 `NativeConversationView` 渲染消息、代码块、输入框、导航与菜单。
iOS 26 及以上直接使用 SwiftUI `glassEffect`（已使用 Xcode 27 / iOS 27 SDK 编译），iOS 17–25 降级到系统 Material；减少透明度和增强对比度使用实色背景。

## 数据接入边界

本项目只有官方 Remote Control URL，没有公开的原生消息 API。当前保留一个不可见的 WKWebView 作为官方连接与登录载体，通过 DOM 桥接提供消息快照。它不负责原生页面的显示；用户可从菜单显式打开同一个网页进行登录、附件、模型选择等操作。

适配器优先识别 Antigravity 2.0 官方会话组件。标记来自本机安装包中的官方 Agent UI Toolkit：

- 会话根节点：`data-testid="conversation-view"` / `data-cascade-id`。
- 用户消息：`data-testid="user-input-step"`。
- 助手正文：目前匹配会话根节点下的 `rendered-markdown` 等容器；尚未在当前账号的真实会话中验证完整性，不能认为已与网页完全一致。
- 输入：Lexical 的 `data-lexical-editor="true"` 与 `contenteditable="true"`。
- 发送：`data-testid="send-button"` / `aria-label="Send message"`。
- 停止：`input-send-button-cancel-tooltip` 对应的取消按钮。

官方 Remote Control 会话链接格式为 `https://antigravity.google.com/r/<instance-id>?p=c%2F<conversation-id>`。其他域名仍只接受显式的 `data-native-*` 或消息角色标记，不会对任意网页猜测输入框或点击表单按钮。

官方首页会读取项目分组和对话列表，原生页面直接展示，并从页面上的真实输入框发送。登录页和不匹配的页面仍显示“等待对话接入”并禁用原生发送。进入某一条对话后，原生页面改为显示该对话的消息。

原生发送通过 `callAsyncJavaScript` 参数传值，不拼接消息字符串。网页已有不同草稿时拒绝覆盖；相同的暂存草稿可以重试，不重复插入。按钮不可用时保留草稿并提示到网页检查。`submitted` 仅表示调用了网页发送按钮，不等同于服务端确认；消息列表仅来自后续网页快照，不插入伪造回复。

## 2026-09-22 功能修复与验证边界

- 每个网页 frame 独立发布快照，原生保存提供当前内容的 `WKFrameInfo`，向同一个 frame 发送操作。当前 frame 的空快照可以清空旧内容，不再用消息数量阻止清空。
- 模型菜单包含普通模型、禁用状态以及带思考强度的两级选项。触发菜单使用 pointer 事件，子菜单使用键盘方向键；关闭原生弹窗时关闭底层网页菜单。
- 模型与用量操作检查返回值、提供失败提示和重试；用量不再被调用两次。菜单查询最多等待约三秒，不无限等待 DOM。
- 系统 PhotosPicker 读取单张图片，转换 JPEG（本地上限 20 MB），通过当前输入区域的 file input 和 change 事件交给网页。返回成功只表示完成页面交接，**不表示服务端上传成功**；仍需核验网页附件预览、错误提示、删除和发送。
- 修复浅色弹窗背景、长代码截断、项目列表初始滚动位置和标题区域文字重叠。

已验证：Xcode 模拟器构建通过；16 项 Node/DOM 回归测试通过。DOM 测试依据本机官方安装包的组件标记构建，不等同于运行官方网页。

实页对照仍待完成：本轮读取了正在运行的模拟器截图，但 Device Hub 电脑操作接口超时，Xcode 设备交互接口要求用户在菜单栏 Xcode MCP 批准项目访问。尚未完成鼠标点击回归，不应将本轮结果标记为完整联调通过。

待验收清单：同一会话的消息条数、顺序、正文与工具记录；模型名称与思考强度；用量分组、百分比及重置时间；图片添加、预览、移除与发送；`@` 引用和 `/` 命令建议；长会话分页。当前 `@`、`/` 原生入口仅插入文本，没有实现网页的完整结构化建议选取。

当前文本桥接保留段落与 fenced code；富媒体、工具专用交互和网页历史分页仍需针对实际服务接入。网页加载新地址时清除旧快照，避免混用会话内容。

## 验证

```bash
cd Tests
npm ci --ignore-scripts
npm test
cd ..
xcodebuild -project AntigravityRemote.xcodeproj -scheme AntigravityRemote -sdk iphonesimulator -derivedDataPath /tmp/antirc-native-build CODE_SIGNING_ALLOWED=NO build
```

Xcode Preview：`NativeConversationView.swift` 中的“原生对话 · Liquid Glass”。Debug 启动参数 `--native-conversation-preview` 可显示本地示例；不连接服务、不发送消息，Release 不包含该入口。

实页验收：登录后切回原生、历史消息顺序、流式更新、发送一次只出现一条消息、停止回复、网页草稿冲突、断线重连、长代码横向滚动、键盘避让、深浅色与辅助功能大字号。
