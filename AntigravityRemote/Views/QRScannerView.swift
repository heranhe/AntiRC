//
//  QRScannerView.swift
//  AntigravityRemote
//
//  扫码介入页（对齐 codex-remo：全屏相机、取景框、圆形玻璃按钮）
//

import AVFoundation
import SwiftUI
import UIKit

public struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    public var onScan: (String) -> Void
    public var onBack: (() -> Void)?

    @State private var scannerError: String?
    @State private var hasCameraPermission = false
    @State private var isCheckingPermission = true
    @State private var showManualInputSheet = false
    @State private var manualInputText = ""

    public init(onBack: (() -> Void)? = nil, onScan: @escaping (String) -> Void) {
        self.onBack = onBack
        self.onScan = onScan
    }

    public var body: some View {
        ZStack {
            DesignToken.screenBG.ignoresSafeArea()

            if isCheckingPermission {
                ProgressView()
                    .tint(.white)
            } else if hasCameraPermission {
                QRCameraPreview { code, reset in
                    handleScan(code, reset: reset)
                }
                .ignoresSafeArea()

                scannerOverlay
            } else {
                cameraPermissionView
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                CircleGlassButton(systemImage: "chevron.left") {
                    HapticManager.light()
                    if let onBack = onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .task { await checkCameraPermission() }
        .alert("无法识别", isPresented: Binding(
            get: { scannerError != nil },
            set: { if !$0 { scannerError = nil } }
        )) {
            Button("好", role: .cancel) { scannerError = nil }
        } message: {
            Text(scannerError ?? "这不是有效的远程连接二维码")
        }
        .sheet(isPresented: $showManualInputSheet) {
            NavigationStack {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("输入或粘贴连接地址")
                            .font(AppFont.headline())
                            .foregroundStyle(.white)

                        Text("可点击电脑端 Antigravity「copy link」复制，或直接输入局域网地址。")
                            .font(AppFont.caption())
                            .foregroundStyle(DesignToken.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .foregroundStyle(Color.blue)
                        TextField("https://...", text: $manualInputText)
                            .font(AppFont.mono(.callout))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .foregroundStyle(.white)

                        if !manualInputText.isEmpty {
                            Button {
                                manualInputText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DesignToken.fillCode)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DesignToken.hairline, lineWidth: 1)
                    )

                    PrimaryCapsuleButton(title: "立即连接", systemImage: "arrow.right.circle.fill") {
                        let trimmed = manualInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let normalized = UserAgentHelper.normalizeRemoteURL(trimmed)
                        guard UserAgentHelper.isValidRemoteURL(normalized) else {
                            HapticManager.error()
                            scannerError = "请输入合法的远程连接地址（如 https://...）"
                            return
                        }
                        showManualInputSheet = false
                        HapticManager.success()
                        onScan(normalized)
                    }

                    Spacer()
                }
                .padding(24)
                .background(DesignToken.screenBG.ignoresSafeArea())
                .navigationTitle("手动输入")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            showManualInputSheet = false
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.medium])
        }
    }

    private var scannerOverlay: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 260, height: 260)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 260, height: 260)
            }

            VStack(spacing: 6) {
                Text("扫描电脑端二维码")
                    .font(AppFont.headline(weight: .semibold))
                    .foregroundStyle(.white)

                Text("请对准 Antigravity 设置 → Application 中的二维码")
                    .font(AppFont.caption())
                    .foregroundStyle(DesignToken.textSecondary)
            }

            SecurityFootnote(text: "端到端加密 · 仅直连你的专属会话")

            Button {
                HapticManager.light()
                if let string = UIPasteboard.general.string, UserAgentHelper.isValidRemoteURL(string) {
                    manualInputText = string
                }
                showManualInputSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 15, weight: .semibold))
                    Text("手动输入连接地址")
                        .font(AppFont.subheadline(weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            }
            .padding(.top, 4)

            Spacer()
        }
    }

    private var cameraPermissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("需要相机权限")
                .font(AppFont.title3(weight: .semibold))
                .foregroundStyle(.white)

            Text("请在系统设置中允许相机访问，以扫描连接二维码。")
                .font(AppFont.subheadline())
                .foregroundStyle(DesignToken.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("打开设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(AppFont.body(weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Capsule().fill(.white))
        }
    }

    private func handleScan(_ code: String, reset: @escaping () -> Void) {
        let normalized = UserAgentHelper.normalizeRemoteURL(code)
        guard UserAgentHelper.isValidRemoteURL(normalized) else {
            HapticManager.error()
            scannerError = "二维码内容不是合法的远程连接地址"
            reset()
            return
        }
        HapticManager.success()
        onScan(normalized)
    }

    @MainActor
    private func checkCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            hasCameraPermission = true
        case .notDetermined:
            hasCameraPermission = await AVCaptureDevice.requestAccess(for: .video)
        default:
            hasCameraPermission = false
        }
        isCheckingPermission = false
    }
}

struct QRCameraPreview: UIViewRepresentable {
    var onCode: (String, @escaping () -> Void) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            return view
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
            output.metadataObjectTypes = [.qr, .ean8, .ean13, .code128]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = UIScreen.main.bounds
        view.layer.addSublayer(preview)

        context.coordinator.session = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let preview = uiView.layer.sublayers?.compactMap({ $0 as? AVCaptureVideoPreviewLayer }).first {
            preview.frame = uiView.bounds
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.session?.stopRunning()
        coordinator.session = nil
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String, @escaping () -> Void) -> Void
        var session: AVCaptureSession?
        private var isLocked = false

        init(onCode: @escaping (String, @escaping () -> Void) -> Void) {
            self.onCode = onCode
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !isLocked,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue
            else { return }

            isLocked = true
            onCode(value) { [weak self] in
                DispatchQueue.main.async {
                    self?.isLocked = false
                }
            }
        }
    }
}
