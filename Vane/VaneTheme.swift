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

enum AutomaticSunAppearance {
    static let enabledKey = "automaticSunAppearance"

    static func appearance(for snapshot: ForecastSnapshot, at date: Date = .now) -> AppAppearance? {
        guard !snapshot.isPlaceholder else { return nil }
        return isDaylight(for: snapshot, at: date) ? .light : .dark
    }

    static func nextTransition(for snapshot: ForecastSnapshot, after date: Date = .now) -> Date? {
        guard !snapshot.isPlaceholder else { return nil }
        return snapshot.daily
            .flatMap { [$0.sunrise, $0.sunset].compactMap { $0 } }
            .filter { $0 > date }
            .min()
    }

    static func isDaylight(for snapshot: ForecastSnapshot, at date: Date = .now) -> Bool {
        let calendar = snapshot.calendar
        if let day = snapshot.daily.first(where: { calendar.isDate($0.date, inSameDayAs: date) }),
           let sunrise = day.sunrise,
           let sunset = day.sunset {
            return date >= sunrise && date < sunset
        }
        return snapshot.current.isDaylight
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

extension WeatherAlertSeverity {
    var tint: Color {
        switch self {
        case .extreme: Color(red: 0.72, green: 0.08, blue: 0.12)
        case .severe: Color(red: 0.90, green: 0.20, blue: 0.13)
        case .moderate: Color(red: 0.91, green: 0.48, blue: 0.06)
        case .minor: Color(red: 0.76, green: 0.57, blue: 0.08)
        case .unknown: VaneTheme.blue
        }
    }

    var symbolName: String {
        switch self {
        case .extreme: "exclamationmark.octagon.fill"
        case .severe: "exclamationmark.triangle.fill"
        case .moderate: "exclamationmark.triangle.fill"
        case .minor: "info.circle.fill"
        case .unknown: "bell.badge.fill"
        }
    }
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
        if condition?.isDaylight == false { return [Color(red: 0.48, green: 0.58, blue: 0.74), Color(red: 0.68, green: 0.76, blue: 0.87), Color(red: 0.86, green: 0.89, blue: 0.95)] }
        if symbol.contains("rain") || symbol.contains("storm") { return [Color(red: 0.35, green: 0.48, blue: 0.62), Color(red: 0.62, green: 0.72, blue: 0.80), Color(red: 0.86, green: 0.90, blue: 0.93)] }
        if symbol.contains("cloud") { return [Color(red: 0.64, green: 0.76, blue: 0.86), Color(red: 0.82, green: 0.88, blue: 0.93), Color(red: 0.96, green: 0.97, blue: 0.98)] }
        return [Color(red: 0.68, green: 0.86, blue: 0.99), Color(red: 0.90, green: 0.96, blue: 1), Color(red: 1.0, green: 0.97, blue: 0.90)]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(usesDarkPalette ? 0.035 : 0.5)).frame(width: 360, height: 360).blur(radius: 70).offset(x: -190, y: -330)
            Circle().fill(VaneTheme.blue.opacity(usesDarkPalette ? 0.12 : 0.08)).frame(width: 480, height: 480).blur(radius: 100).offset(x: 220, y: 320)
            skyDecoration
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var skyDecoration: some View {
        if let condition {
            if condition.isDaylight, condition.symbolName.lowercased().contains("sun") {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(usesDarkPalette ? 0.08 : 0.18))
                        .frame(width: 210, height: 210)
                        .blur(radius: 34)
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 96, weight: .light))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.yellow.opacity(0.30), Color.orange.opacity(0.15))
                }
                .offset(x: 145, y: -330)
                .accessibilityHidden(true)
            } else if !condition.isDaylight {
                ZStack {
                    ForEach(0..<14, id: \.self) { index in
                        Circle()
                            .fill(Color.white.opacity(usesDarkPalette ? 0.30 : 0.38))
                            .frame(width: index.isMultiple(of: 3) ? 4 : 2, height: index.isMultiple(of: 3) ? 4 : 2)
                            .offset(x: CGFloat((index * 47) % 330) - 155, y: CGFloat((index * 83) % 430) - 310)
                    }
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 82, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.white.opacity(usesDarkPalette ? 0.34 : 0.46))
                        .offset(x: 128, y: -315)
                }
                .accessibilityHidden(true)
            }
        }
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = 28
    var dark = false
    var tint: Color?
    let content: Content

    init(radius: CGFloat = 28, dark: Bool = false, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.dark = dark
        self.tint = tint
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(tint ?? (dark ? Color.white.opacity(0.035) : nil)),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(colorScheme == .dark ? 0.18 : 0.46), .white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                }
                .shadow(color: VaneTheme.deepInk.opacity(colorScheme == .dark ? 0.20 : 0.075), radius: 22, y: 11)
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill((tint ?? (dark || colorScheme == .dark ? .black : .white)).opacity(tint == nil ? 0.12 : 0.08))
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.38), lineWidth: 0.75)
                }
                .shadow(color: VaneTheme.deepInk.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 20, y: 10)
        }
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
