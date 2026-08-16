import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum VaneTheme {
    static let deepInk = Color(red: 0.025, green: 0.075, blue: 0.14)
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.92, green: 0.96, blue: 1, alpha: 1)
            : UIColor(red: 0.025, green: 0.075, blue: 0.14, alpha: 1)
    })
    static let blue = Color(red: 0.10, green: 0.43, blue: 0.96)
    static let cyan = Color(red: 0.20, green: 0.73, blue: 0.92)
    static let sky = Color(red: 0.55, green: 0.78, blue: 0.96)
    static let paleSky = Color(red: 0.90, green: 0.96, blue: 1.0)
    static let muted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.63, green: 0.71, blue: 0.82, alpha: 1)
            : UIColor(red: 0.24, green: 0.34, blue: 0.46, alpha: 1)
    })
    static let warm = Color(red: 1.0, green: 0.69, blue: 0.35)
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.095, blue: 0.15, alpha: 0.78)
            : UIColor(white: 1, alpha: 0.5)
    })
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.08)
            : UIColor(red: 0.025, green: 0.075, blue: 0.14, alpha: 0.08)
    })
}

struct AtmosphericBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var dark = false
    var condition: CurrentConditions?

    init(dark: Bool = false, condition: CurrentConditions? = nil) {
        self.dark = dark
        self.condition = condition
    }

    // Appearance controls light vs. dark. Weather can still influence the
    // light palette, but nighttime should never override an explicit Light choice.
    private var usesDarkPalette: Bool { dark || colorScheme == .dark }

    private var palette: [Color] {
        guard !usesDarkPalette else { return [Color(red: 0.008, green: 0.025, blue: 0.055), Color(red: 0.018, green: 0.065, blue: 0.12), Color(red: 0.025, green: 0.10, blue: 0.19)] }
        let symbol = condition?.symbolName.lowercased() ?? ""
        if symbol.contains("rain") || symbol.contains("storm") { return [Color(red: 0.35, green: 0.48, blue: 0.62), Color(red: 0.62, green: 0.72, blue: 0.80), Color(red: 0.86, green: 0.90, blue: 0.93)] }
        if symbol.contains("cloud") { return [Color(red: 0.64, green: 0.76, blue: 0.86), Color(red: 0.82, green: 0.88, blue: 0.93), Color(red: 0.96, green: 0.97, blue: 0.98)] }
        return [Color(red: 0.68, green: 0.86, blue: 0.99), Color(red: 0.90, green: 0.96, blue: 1), Color(red: 1.0, green: 0.97, blue: 0.90)]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(usesDarkPalette ? 0.035 : 0.5)).frame(width: 360, height: 360).blur(radius: 70).offset(x: -190, y: -330)
            Circle().fill(VaneTheme.blue.opacity(usesDarkPalette ? 0.12 : 0.08)).frame(width: 480, height: 480).blur(radius: 100).offset(x: 220, y: 320)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = 28
    var dark = false
    let content: Content

    init(radius: CGFloat = 28, dark: Bool = false, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.dark = dark
        self.content = content()
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill((dark || colorScheme == .dark ? Color.black : Color.white).opacity(dark || colorScheme == .dark ? 0.12 : 0.12))
                    }
            }
            .shadow(color: VaneTheme.deepInk.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 20, y: 10)
    }
}

struct SectionKicker: View {
    let title: String
    var dark = false

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.25)
            .foregroundStyle(dark ? .white.opacity(0.52) : VaneTheme.muted.opacity(0.72))
    }
}

struct VaneMark: View {
    var size: CGFloat = 44

    var body: some View {
        Image("Vane")
            .resizable()
            .aspectRatio(1187 / 557, contentMode: .fit)
            .frame(width: size, height: size * 0.47)
        .accessibilityHidden(true)
    }
}

private struct VaneLiquidGlassButtonModifier: ViewModifier {
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func vaneLiquidGlassButton(prominent: Bool = false) -> some View {
        modifier(VaneLiquidGlassButtonModifier(prominent: prominent))
    }
}
