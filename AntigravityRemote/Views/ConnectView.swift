//
//  ConnectView.swift
//  AntigravityRemote
//
//  开屏引导 + 连接大厅（对齐 codex-remo / Remodex 的原生对话式操作逻辑）
//

import SwiftUI

/// 连接大厅：首次开屏引导 / 已有设备列表 / 扫码介入
public struct ConnectView: View {
    @ObservedObject public var settings: AppSettings
    public var onConnect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage = 0
    @State private var showScanner = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showDemo = false
    @State private var clipboardCandidateURL: String?
    @State private var isManualInputExpanded = false
    @State private var manualInputURL = ""
    @State private var editingRecord: ConnectionRecord?
    @State private var editingAliasText = ""
    @State private var showRenameAlert = false

    private let pageCount = 3

    public init(settings: AppSettings, onConnect: @escaping (String) -> Void) {
        self.settings = settings
        self.onConnect = onConnect
    }

    public var body: some View {
        ZStack {
            DesignToken.screenBG.ignoresSafeArea()

            if !settings.hasCompletedOnboarding {
                onboardingBody
            } else {
                homeBody
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showScanner) {
            QRScannerView(onBack: {
                showScanner = false
            }) { code in
                handleScannedCode(code)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(settings: settings) { url in
                initiateConnect(with: url)
            }
        }
        .fullScreenCover(isPresented: $showDemo) {
            DemoConversationView { showDemo = false }
        }
        .alert("修改账户备注", isPresented: $showRenameAlert) {
            TextField("输入自定义备注（如：工位 Mac）", text: $editingAliasText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                if let record = editingRecord {
                    HapticManager.light()
                    settings.updateAccountInfo(id: record.id, alias: editingAliasText)
                }
            }
        } message: {
            Text("为该账户或设备设置一个易于识别的名称")
        }
        .onAppear {
            settings.updateIdleTimer()
            detectClipboard()
        }
    }

    // MARK: - Onboarding (first run)

    private var onboardingBody: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    startPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 14) {
                    PageDotsIndicator(count: pageCount, current: currentPage)

                    if currentPage == pageCount - 1 {
                        PrimaryCapsuleButton(title: "扫描电脑端二维码", systemImage: "qrcode.viewfinder") {
                            finishOnboarding(openScanner: true)
                        }

                        Button("免登录体验演示") {
                            finishOnboarding(openScanner: false)
                            showDemo = true
                        }
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)

                        Button {
                            finishOnboarding(openScanner: false)
                        } label: {
                            Text("稍后扫码，进入连接大厅")
                                .font(AppFont.caption(weight: .medium))
                                .foregroundStyle(DesignToken.textSecondary)
                        }
                        .padding(.top, -2)
                    } else {
                        PrimaryCapsuleButton(title: "继续") {
                            advanceOnboarding()
                        }
                    }

                    SecurityFootnote(text: "端到端安全连接 · 数据仅在设备间传输")
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 14))
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.92), .black],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .ignoresSafeArea()
                )
            }
        }
    }

    private var welcomePage: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 12)

                remoteSessionHero
                    .frame(height: min(geo.size.height * 0.50, 390))

                VStack(spacing: 13) {
                    brandLogo
                        .shadow(color: Color.blue.opacity(0.45), radius: 20, y: 8)

                    Text("AntiRC")
                        .font(AppFont.display())
                        .foregroundStyle(.white)
                        .tracking(-0.8)

                    Text("在你的 iPhone 上，随时掌控 Antigravity")
                        .font(AppFont.subheadline())
                        .foregroundStyle(DesignToken.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(onboardingGlow)
        }
    }

    private var remoteSessionHero: some View {
        ZStack {
            onboardingPhone(kind: .terminal)
                .frame(width: 184, height: 355)
                .rotationEffect(.degrees(-5))
                .offset(x: -54, y: -2)

            onboardingPhone(kind: .conversation)
                .frame(width: 164, height: 316)
                .rotationEffect(.degrees(4))
                .offset(x: 62, y: 42)
                .shadow(color: .black.opacity(0.7), radius: 18, x: -8, y: 8)
        }
        .scaleEffect(reduceMotion ? 1 : 1.02)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("电脑终端与手机远程会话预览")
    }

    private enum PreviewKind: Equatable {
        case terminal
        case conversation
    }

    private func onboardingPhone(kind: PreviewKind) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.17, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.065, blue: 0.075))
                    .overlay(
                        RoundedRectangle(cornerRadius: width * 0.17, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                    )

                RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                    .fill(Color(red: 0.965, green: 0.97, blue: 0.985))
                    .padding(width * 0.045)
                    .overlay {
                        if kind == .terminal {
                            terminalPreview
                                .padding(width * 0.09)
                        } else {
                            conversationPreview
                                .padding(width * 0.09)
                        }
                    }

                Capsule()
                    .fill(Color.black)
                    .frame(width: width * 0.34, height: width * 0.09)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, width * 0.07)
            }
        }
    }

    private var terminalPreview: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 6, height: 6)
                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 6, height: 6)
                Circle().fill(Color.green.opacity(0.8)).frame(width: 6, height: 6)
            }
            Text("ANTIGRAVITY")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.black.opacity(0.78))
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(index == 2 ? Color.blue.opacity(0.75) : Color.black.opacity(index.isMultiple(of: 3) ? 0.35 : 0.16))
                    .frame(width: index.isMultiple(of: 2) ? 98 : 124, height: 4)
            }
            Spacer()
            HStack(spacing: 5) {
                Text(">_")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.blue)
                Capsule().fill(Color.black.opacity(0.18)).frame(height: 5)
            }
        }
        .padding(.top, 18)
    }

    private var conversationPreview: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle().fill(Color.blue.opacity(0.12)).frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            Text("Hi, how can I help you?")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.black.opacity(0.78))
            Text("会话已安全连接")
                .font(.system(size: 6.5, weight: .medium))
                .foregroundStyle(.black.opacity(0.4))
            Spacer()
            Capsule()
                .fill(Color.black.opacity(0.08))
                .frame(height: 24)
                .overlay(alignment: .trailing) {
                    Circle().fill(.black).frame(width: 18, height: 18).padding(3)
                }
        }
        .padding(.top, 18)
    }

    private var onboardingGlow: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [Color.blue.opacity(0.20), Color.cyan.opacity(0.06), .clear],
                center: UnitPoint(x: 0.5, y: 0.18),
                startRadius: 10,
                endRadius: 310
            )
        }
        .ignoresSafeArea()
    }

    private var brandLogo: some View {
        Group {
            if UIImage(named: "AppLogo") != nil {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    /// 顶栏小号品牌标（避免 home 过大）
    private var homeLogo: some View {
        Group {
            if UIImage(named: "AppLogo") != nil {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var featuresPage: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 18)

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.16))
                    .frame(width: 230, height: 230)
                    .blur(radius: 10)
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 92, weight: .ultraLight))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("远程操作，也能像在电脑前一样")
                    .font(AppFont.title2(weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("外网直连、原生终端键位与安全区适配，\n让每一次远程控制都清晰顺手。")
                    .font(AppFont.subheadline())
                    .foregroundStyle(DesignToken.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "network", title: "无需公网 IP", detail: "4G / 5G 与任意 Wi-Fi 都能连接")
                featureRow(icon: "keyboard", title: "为终端而生", detail: "Esc、Tab、Ctrl+C 与方向键触手可及")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(DesignToken.fillCard))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(DesignToken.hairline))

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 24)
        .background(onboardingGlow)
    }

    private var startPage: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            macSettingsIllustration
                .padding(.horizontal, 4)

            VStack(spacing: 6) {
                Text("一扫，就连接")
                    .font(AppFont.title2(weight: .bold))
                    .foregroundStyle(.white)
                Text("打开电脑端 Antigravity「Settings → Application」，\n开启 Remote Control 即可扫码进入会话。")
                    .font(AppFont.subheadline())
                    .foregroundStyle(DesignToken.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(spacing: 9) {
                stepCard(
                    number: "1",
                    title: "电脑端打开 Application 设置",
                    detail: "打开 Antigravity，进入 Settings (⌘,) → Application"
                )
                stepCard(
                    number: "2",
                    title: "开启 Remote Control 并扫码",
                    detail: "开启 Enable 开关，用手机扫描右侧生成的专属二维码"
                )
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .background(onboardingGlow)
    }

    /// 拟真电脑端 Antigravity Settings -> Application 面板
    private var macSettingsIllustration: some View {
        VStack(spacing: 0) {
            // macOS 窗口标题栏
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 8, height: 8)

                Spacer()
                Text("Antigravity · Settings")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()

                Circle().fill(Color.clear).frame(width: 8, height: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))

            Divider().background(Color.white.opacity(0.08))

            // 窗口主体：左侧菜单 + 右侧内容
            HStack(spacing: 0) {
                // 左侧 Sidebar
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.bottom, 2)

                    sidebarItem(title: "General", isSelected: false)
                    sidebarItem(title: "Application", isSelected: true)
                    sidebarItem(title: "Appearance", isSelected: false)
                    sidebarItem(title: "Models", isSelected: false)

                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(width: 96)
                .background(Color.white.opacity(0.025))

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                // 右侧 Application > Remote Control
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Application")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Remote Control")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(Color.blue)
                        }
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Remote Control")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Work with local agents")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer()

                            // 开关亮起状态
                            ZStack(alignment: .trailing) {
                                Capsule()
                                    .fill(Color.blue)
                                    .frame(width: 26, height: 14)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 11, height: 11)
                                    .padding(.trailing, 1.5)
                            }
                        }

                        // 设备名与右侧真实二维码
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Device Name")
                                    .font(.system(size: 6.5))
                                    .foregroundStyle(.white.opacity(0.45))
                                Text("Mac-Mini-Remote")
                                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(4)

                                Text("Scan code to open device,\nor copy link.")
                                    .font(.system(size: 6.5))
                                    .foregroundStyle(.blue.opacity(0.95))
                                    .lineSpacing(2)
                                    .padding(.top, 1)
                            }

                            Spacer(minLength: 4)

                            macMiniQRCode
                        }
                        .padding(5)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)

                    Spacer(minLength: 0)
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 195)
        .background(Color(red: 0.08, green: 0.085, blue: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.blue.opacity(0.35), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.blue.opacity(0.22), radius: 20, y: 8)
    }

    /// 高拟真二维码组件（黑白清晰、带科技瞄准角标）
    private var macMiniQRCode: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white)
                .frame(width: 54, height: 54)

            Image(systemName: "qrcode")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Color.black)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.85), lineWidth: 1.5)
                .frame(width: 58, height: 58)
        }
    }

    private func sidebarItem(title: String, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            if isSelected {
                Circle().fill(Color.blue).frame(width: 3.5, height: 3.5)
            }
            Text(title)
                .font(.system(size: 8, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .background(
            isSelected ? Color.blue.opacity(0.30) : Color.clear
        )
        .cornerRadius(4)
    }

    private func advanceOnboarding() {
        HapticManager.light()
        if currentPage < pageCount - 1 {
            withAnimation(reduceMotion ? DesignToken.fade : DesignToken.pageSpring) {
                currentPage += 1
            }
        } else {
            finishOnboarding(openScanner: true)
        }
    }

    private func finishOnboarding(openScanner: Bool) {
        HapticManager.medium()
        withAnimation(DesignToken.fade) {
            settings.completeOnboarding()
        }
        if openScanner {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showScanner = true
            }
        }
    }

    // MARK: - Home (has devices)

    private var homeBody: some View {
        VStack(spacing: 0) {
            homeHeader

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        if let clip = clipboardCandidateURL {
                            clipboardBanner(url: clip)
                        }

                        if isManualInputExpanded {
                            manualInputCard
                        }

                        devicesSection

                        if settings.showNewbieHelpTips {
                            Spacer(minLength: 16)
                            helpSection
                        }

                        demoEntry
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .frame(minHeight: proxy.size.height)
                }
            }

            BottomFadeBar {
                PrimaryCapsuleButton(title: "扫描电脑端二维码", systemImage: "qrcode") {
                    HapticManager.medium()
                    showScanner = true
                }
            }
        }
    }

    private var homeHeader: some View {
        HStack(spacing: 12) {
            homeLogo

            VStack(alignment: .leading, spacing: 2) {
                Text("AntiRC")
                    .font(AppFont.headline())
                    .foregroundStyle(.white)
                Text("选择一台电脑开始操控")
                    .font(AppFont.caption())
                    .foregroundStyle(DesignToken.textSecondary)
            }

            Spacer()

            CircleGlassButton(systemImage: "gearshape") {
                HapticManager.light()
                showSettings = true
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近连接")
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(DesignToken.textSecondary)
                Spacer()
                if !settings.historyList.isEmpty {
                    Button("全部历史") {
                        HapticManager.light()
                        showHistory = true
                    }
                    .font(AppFont.caption(weight: .medium))
                    .foregroundStyle(DesignToken.textSecondary)
                }
            }

            if settings.historyList.isEmpty {
                emptyDevicesCard
            } else {
                ForEach(settings.historyList.prefix(6)) { record in
                    deviceRow(record)
                }
            }
        }
    }

    private var demoEntry: some View {
        Button {
            HapticManager.light()
            showDemo = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .medium))
                Text("免登录体验演示")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("demoEntry")
    }

    private var emptyDevicesCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.blue.opacity(0.85))
                .padding(.top, 4)

            VStack(spacing: 4) {
                Text("暂无已连接设备")
                    .font(AppFont.body(weight: .semibold))
                    .foregroundStyle(.white)
                Text("参考下方指引在电脑端 Antigravity 开启 Remote Control，点击下方按钮开始扫码。")
                    .font(AppFont.caption())
                    .foregroundStyle(DesignToken.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignToken.fillCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignToken.hairline, lineWidth: 1)
        )
    }

    private func deviceRow(_ record: ConnectionRecord) -> some View {
        let isConnected = record.status == .connected
        return Button {
            HapticManager.medium()
            initiateConnect(with: record.urlString)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isConnected ? Color.green.opacity(0.16) : DesignToken.fillSoft)
                        .frame(width: 44, height: 44)
                    Image(systemName: isConnected ? "desktopcomputer" : "display")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isConnected ? Color.green : .white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(record.deviceTitle)
                            .font(AppFont.body(weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if isConnected {
                            Text("已连通")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        }
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 11))
                        Text(record.accountSubtitle)
                            .font(AppFont.caption())
                    }
                    .foregroundStyle(DesignToken.textSecondary)
                    .lineLimit(1)
                }

                Spacer()

                statusDot(record.status)

                Button {
                    HapticManager.light()
                    editingRecord = record
                    editingAliasText = record.deviceAlias ?? ""
                    showRenameAlert = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignToken.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isConnected ? Color(red: 0.05, green: 0.09, blue: 0.06) : DesignToken.fillCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isConnected ? Color.green.opacity(0.35) : DesignToken.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("重命名") {
                editingRecord = record
                editingAliasText = record.deviceAlias ?? ""
                showRenameAlert = true
            }
            Button("删除记录", role: .destructive) {
                settings.removeConnection(id: record.id)
            }
        }
    }

    private func statusDot(_ status: ConnectionStatus) -> some View {
        ZStack {
            if status == .connected {
                Circle()
                    .fill(Color.green.opacity(0.35))
                    .frame(width: 14, height: 14)
            }
            Circle()
                .fill(status == .connected ? Color.green : DesignToken.textTertiary)
                .frame(width: 8, height: 8)
        }
    }

    private var manualInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接地址")
                .font(AppFont.subheadline(weight: .semibold))
                .foregroundStyle(.white)

            TextField("https://...", text: $manualInputURL)
                .font(AppFont.mono(.caption))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DesignToken.fillCode)
                )
                .foregroundStyle(.white)

            PrimaryCapsuleButton(title: "连接") {
                let trimmed = manualInputURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                HapticManager.medium()
                settings.saveConnection(urlString: trimmed)
                initiateConnect(with: trimmed)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DesignToken.fillCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignToken.hairline, lineWidth: 1)
        )
    }

    private var manualInputSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("https://...", text: $manualInputURL)
                    .font(AppFont.mono(.caption))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DesignToken.fillCode)
                    )
                    .foregroundStyle(.white)

                PrimaryCapsuleButton(title: "连接") {
                    let trimmed = manualInputURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    HapticManager.medium()
                    settings.saveConnection(urlString: trimmed)
                    isManualInputExpanded = false
                    initiateConnect(with: trimmed)
                }

                Spacer()
            }
            .padding(24)
            .background(DesignToken.screenBG.ignoresSafeArea())
            .navigationTitle("输入连接地址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isManualInputExpanded = false }
                        .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.blue)
                    Text("电脑端扫码步骤")
                        .font(AppFont.subheadline(weight: .semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    withAnimation(DesignToken.fade) {
                        HapticManager.light()
                        settings.showNewbieHelpTips = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("关闭")
                            .font(AppFont.caption2(weight: .medium))
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(DesignToken.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            stepCard(
                number: "1",
                title: "打开 Antigravity 设置",
                detail: "在 Mac 打开 Antigravity，进入 Settings 设置 (快捷键 ⌘,)"
            )
            stepCard(
                number: "2",
                title: "进入 Application 设置项",
                detail: "左侧菜单切换到「Application」，找到「Remote Control」"
            )
            stepCard(
                number: "3",
                title: "开启开关并扫码连接",
                detail: "打开「Enable Remote Control」，用下方按钮扫码或点击 copy link"
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DesignToken.fillCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignToken.hairline, lineWidth: 1)
        )
    }

    // MARK: - Shared pieces

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(DesignToken.fillSoft))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.body(weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(AppFont.caption())
                    .foregroundStyle(DesignToken.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepCard(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(AppFont.caption2(weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(AppFont.caption())
                    .foregroundStyle(DesignToken.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DesignToken.fillCode)
                    )
            }
        }
    }

    private func clipboardBanner(url: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("检测到连接地址")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(.white)
                Text(url)
                    .font(AppFont.caption2())
                    .foregroundStyle(DesignToken.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("连接") {
                HapticManager.medium()
                initiateConnect(with: url)
            }
            .font(AppFont.caption(weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignToken.hairline, lineWidth: 1)
        )
    }

    // MARK: - Actions (security-preserving)

    private func detectClipboard() {
        guard settings.hasCompletedOnboarding else { return }
        guard settings.autoFillClipboard else { return }
        guard UIPasteboard.general.hasStrings else { return }
        if let string = UIPasteboard.general.string,
           UserAgentHelper.isValidRemoteURL(string) {
            withAnimation(DesignToken.fade) {
                clipboardCandidateURL = string
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        showScanner = false
        let normalized = UserAgentHelper.normalizeRemoteURL(code)
        guard UserAgentHelper.isValidRemoteURL(normalized) else {
            HapticManager.error()
            return
        }
        HapticManager.success()
        settings.saveConnection(urlString: normalized)
        initiateConnect(with: normalized)
    }

    private func initiateConnect(with urlString: String) {
        let normalized = UserAgentHelper.normalizeRemoteURL(urlString)
        settings.saveConnection(urlString: normalized)
        onConnect(normalized)
    }
}
