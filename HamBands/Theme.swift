import SwiftUI

// MARK: - App theme

/// The look of the app. `retro` is the hidden "early internet" easter-egg theme,
/// unlocked from the secret alert (tap the "HamBand" title five times).
enum AppTheme: String {
    case modern
    case retro

    /// Key used with @AppStorage so the choice survives relaunches.
    static let storageKey = "appTheme"
}

enum Retro {
    /// Classic Windows 95 / Netscape window grey.
    static let grey = Color(red: 0.75, green: 0.75, blue: 0.75)
    /// The default hyperlink blue of 1990s browsers.
    static let linkBlue = Color(red: 0.0, green: 0.0, blue: 0.93)
    /// Title-bar navy.
    static let navy = Color(red: 0.0, green: 0.0, blue: 0.5)
    static let darkShadow = Color(red: 0.5, green: 0.5, blue: 0.5)
}

// MARK: - Card background

/// Draws a card behind its content: a soft rounded material in the modern theme,
/// or a raised, bevelled grey box in the retro theme.
private struct ThemedCard: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .modern
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        switch theme {
        case .modern:
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        case .retro:
            content
                .background(Retro.grey)
                // Light top/left edges + dark bottom/right edges = the 3D "raised" look.
                .overlay(alignment: .bottom) { Retro.darkShadow.frame(height: 2) }
                .overlay(alignment: .trailing) { Retro.darkShadow.frame(width: 2) }
                .overlay(alignment: .top) { Color.white.frame(height: 2) }
                .overlay(alignment: .leading) { Color.white.frame(width: 2) }
        }
    }
}

// MARK: - Screen background and app-wide styling

/// Fills a screen with the retro grey; does nothing in the modern theme.
private struct ThemedScreenBackground: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .modern

    func body(content: Content) -> some View {
        if theme == .retro {
            content.background(Retro.grey.ignoresSafeArea())
        } else {
            content
        }
    }
}

/// App-wide styling applied once at the root: serif "Times New Roman" type,
/// link-blue tint and a forced light appearance while retro is on.
private struct ThemedRoot: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .modern

    func body(content: Content) -> some View {
        if theme == .retro {
            content
                .fontDesign(.serif)
                .tint(Retro.linkBlue)
                .preferredColorScheme(.light)
        } else {
            content
        }
    }
}

extension View {
    func themedCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(ThemedCard(cornerRadius: cornerRadius))
    }

    func themedScreenBackground() -> some View {
        modifier(ThemedScreenBackground())
    }

    func themedRoot() -> some View {
        modifier(ThemedRoot())
    }
}

// MARK: - Retro-only banner

/// A very 1997 welcome banner, shown at the top of the Bands tab in retro mode.
struct RetroWelcomeBanner: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("★ Welcome to HamBand! ★")
                .font(.system(.headline, design: .serif).weight(.bold))
                .foregroundStyle(.yellow)
            Text("Best viewed in Netscape Navigator 4.0 at 800×600")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Retro.navy)
        .padding(.horizontal)
    }
}
