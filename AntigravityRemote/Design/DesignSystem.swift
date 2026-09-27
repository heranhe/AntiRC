//
//  DesignSystem.swift
//  AntigravityRemote
//
//  对齐 codex-remo（Remodex）视觉与动效：纯黑底、白胶囊 CTA、自适应玻璃、统一字号
//

import SwiftUI

// MARK: - Fonts

enum AppFont {
    static func body(weight: Font.Weight = .regular) -> Font {
        .system(size: 15, weight: weight)
    }

    static func callout(weight: Font.Weight = .regular) -> Font {
        .system(size: 14.5, weight: weight)
    }

    static func subheadline(weight: Font.Weight = .regular) -> Font {
        .system(size: 14, weight: weight)
    }

    static func footnote(weight: Font.Weight = .regular) -> Font {
        .system(size: 12, weight: weight)
    }

    static func caption(weight: Font.Weight = .regular) -> Font {
        .system(size: 11, weight: weight)
    }

    static func caption2(weight: Font.Weight = .regular) -> Font {
        .system(size: 10, weight: weight)
    }

    static func headline(weight: Font.Weight = .bold) -> Font {
        .system(size: 15.5, weight: weight)
    }

    static func title2(weight: Font.Weight = .bold) -> Font {
        .system(size: 20, weight: weight)
    }

    static func title3(weight: Font.Weight = .medium) -> Font {
        .system(size: 18, weight: weight)
    }

    static func display(weight: Font.Weight = .bold) -> Font {
        .system(size: 32, weight: weight)
    }

    static func mono(_ style: Font.TextStyle = .body) -> Font {
        switch style {
        case .body: return .system(size: 15, design: .monospaced)
        case .caption: return .system(size: 11, design: .monospaced)
        case .caption2: return .system(size: 10, design: .monospaced)
        default: return .system(size: 13, design: .monospaced)
        }
    }

    static func system(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Glass

enum GlassPreference {
    static let storageKey = "antirc.useLiquidGlass"

    static var isSupported: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }
}

private struct AdaptiveGlassModifier<S: Shape>: ViewModifier {
    @AppStorage(GlassPreference.storageKey) private var glassEnabled = true
    let regularStyle: Bool
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26, *), glassEnabled {
            if regularStyle {
                content.glassEffect(.regular, in: shape)
            } else {
                content.glassEffect(in: shape)
            }
        } else {
            content.background(.thinMaterial, in: shape)
        }
    }
}

enum AdaptiveGlassStyle {
    case regular
}

extension View {
    func adaptiveGlass(_ style: AdaptiveGlassStyle, in shape: some Shape) -> some View {
        modifier(AdaptiveGlassModifier(regularStyle: true, shape: shape))
    }

    func adaptiveGlass(in shape: some Shape) -> some View {
        modifier(AdaptiveGlassModifier(regularStyle: false, shape: shape))
    }
}

// MARK: - Tokens

enum DesignToken {
    static let screenBG = Color.black
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)
    static let hairline = Color.white.opacity(0.18)
    static let fillSoft = Color.white.opacity(0.10)
    static let fillCard = Color.white.opacity(0.06)
    static let fillCode = Color.white.opacity(0.08)
    static let accent = Color.white
    static let danger = Color.orange

    static let pageSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let fade = Animation.easeInOut(duration: 0.3)
    static let micro = Animation.easeInOut(duration: 0.2)
}

enum Motion {
    static let page = DesignToken.fade
    static let spring = DesignToken.pageSpring
    static let springTight = DesignToken.micro
}

// MARK: - Buttons

struct PrimaryCapsuleButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage, !systemImage.isEmpty {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(AppFont.body(weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryCapsuleButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage, !systemImage.isEmpty {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(AppFont.body(weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(DesignToken.fillSoft))
            .overlay(Capsule().stroke(DesignToken.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct CircleGlassButton: View {
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct PageDotsIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.white : Color.white.opacity(0.18))
                    .frame(width: i == current ? 24 : 8, height: 8)
            }
        }
        .animation(DesignToken.pageSpring, value: current)
    }
}

struct SecurityFootnote: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(AppFont.caption(weight: .medium))
        }
        .foregroundStyle(DesignToken.textSecondary)
    }
}

struct BottomFadeBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 20) {
            content
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
            .offset(y: -40),
            alignment: .top
        )
    }
}
