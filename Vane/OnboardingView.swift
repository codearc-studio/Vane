import CoreLocation
import SwiftData
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Bindable var store: WeatherStore
    @Bindable var notifications: NotificationManager
    @State private var page = Int(ProcessInfo.processInfo.environment["VANE_ONBOARDING_PAGE"] ?? "") ?? 0
    @State private var temperaturePreference = 0.0
    @State private var windSensitivity = 0.5
    @State private var pageIsVisible = false
    @State private var logoIsFloating = false
    let onComplete: () -> Void

    private let pageCount = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AtmosphericBackground()
                Circle()
                    .fill(accentColor.opacity(0.16))
                    .frame(width: 330, height: 330)
                    .blur(radius: 64)
                    .offset(x: page.isMultiple(of: 2) ? 175 : -175, y: -260)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: page)

                VStack(spacing: 0) {
                    navigation

                    ZStack {
                        currentPage
                            .frame(width: proxy.size.width)
                            .id(page)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .offset(x: 44).combined(with: .opacity),
                                removal: .offset(x: -32).combined(with: .opacity)
                            ))
                    }
                    .frame(width: proxy.size.width)
                    .frame(maxHeight: .infinity)
                    .clipped()

                    controls
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .safeAreaPadding(.top, 4)
                .safeAreaPadding(.bottom, 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .tint(VaneTheme.blue)
        .onAppear {
            pageIsVisible = true
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                logoIsFloating = true
            }
        }
        .onChange(of: page) { _, _ in
            pageIsVisible = false
            withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.18).delay(0.08)) {
                pageIsVisible = true
            }
        }
    }

    private var navigation: some View {
        HStack {
            if page > 0 {
                Button { move(to: page - 1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 42, height: 42)
            }

            Spacer()
        }
        .foregroundStyle(VaneTheme.ink)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 54)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? accentColor : VaneTheme.ink.opacity(0.16))
                        .frame(width: index == page ? 24 : 7, height: 7)
                        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: page)
                }
            }

            VaneGlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if isSkippable {
                        Button { move(to: page + 1) } label: {
                            Text("Skip")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        }
                            .foregroundStyle(VaneTheme.ink)
                            .vaneLiquidGlassButton()
                            .frame(maxWidth: .infinity)
                    }

                    Button(action: primaryAction) {
                        HStack(spacing: 8) {
                            Text(primaryTitle)
                            Image(systemName: page == pageCount - 1 ? "arrow.right" : "chevron.right")
                                .font(.caption.bold())
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .tint(accentColor)
                    .vaneLiquidGlassButton(prominent: true)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var currentPage: some View {
        switch page {
        case 0: welcome
        case 1: temperatureQuestion
        case 2: windQuestion
        case 3: locationPermission
        case 4: notificationPermission
        default: privacy
        }
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 42)
            VaneMark(size: 170)
                .scaleEffect(logoIsFloating ? 1.035 : 0.98)
                .offset(y: logoIsFloating ? -5 : 5)
                .shadow(color: VaneTheme.blue.opacity(0.16), radius: 28, y: 14)

            VStack(spacing: 14) {
                Text("Weather, the way\nit feels to you.")
                    .font(.system(size: 43, weight: .bold, design: .rounded))
                    .tracking(-1.8)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VaneTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Vane keeps the forecast familiar, then adds a personal point of view.")
                    .font(.title3)
                    .foregroundStyle(VaneTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private var temperatureQuestion: some View {
        CalibrationPage(
            title: "Where does comfortable begin?",
            subtitle: "Set a starting point. Vane will refine it from real weather moments.",
            symbol: "thermometer.medium",
            accent: VaneTheme.warm,
            isVisible: pageIsVisible
        ) {
            VStack(spacing: 20) {
                Text(temperaturePreferenceLabel)
                    .font(.title3.bold())
                    .foregroundStyle(VaneTheme.ink)
                    .contentTransition(.numericText())
                Slider(value: $temperaturePreference, in: -1...1)
                    .tint(VaneTheme.warm)
                    .accessibilityLabel("Temperature comfort")
                    .accessibilityValue(temperaturePreferenceLabel)
                HStack {
                    Text("I run cold")
                    Spacer()
                    Text("I run warm")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(VaneTheme.muted)
            }
        }
    }

    private var windQuestion: some View {
        CalibrationPage(
            title: "How much does wind change things?",
            subtitle: "A breezy 70° can land differently. Give Sense a useful starting point.",
            symbol: "wind",
            accent: VaneTheme.cyan,
            isVisible: pageIsVisible
        ) {
            VaneGlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    ChoiceRow(title: "I notice it quickly", isSelected: windSensitivity == 1) { selectWind(1) }
                    ChoiceRow(title: "It depends", isSelected: windSensitivity == 0.5) { selectWind(0.5) }
                    ChoiceRow(title: "It rarely changes the feel", isSelected: windSensitivity == 0) { selectWind(0) }
                }
            }
        }
    }

    private var locationPermission: some View {
        PermissionPage(
            title: "Your forecast starts where you are.",
            subtitle: "Allow location while using Vane for live local weather. You can still search places manually.",
            symbol: "location.fill",
            accent: VaneTheme.blue,
            status: locationStatus,
            actionTitle: locationActionTitle,
            isVisible: pageIsVisible
        ) {
            store.requestCurrentLocation()
        }
    }

    private var notificationPermission: some View {
        PermissionPage(
            title: "A heads-up, only when it helps.",
            subtitle: "Vane can quietly flag likely rain, sharp temperature shifts, and strong UV. No engagement nudges.",
            symbol: "bell.badge.fill",
            accent: VaneTheme.warm,
            status: notificationStatus,
            actionTitle: notificationActionTitle,
            isVisible: pageIsVisible
        ) {
            Task { await notifications.requestUsefulAlerts() }
        }
    }

    private var privacy: some View {
        CalibrationPage(
            title: "What Vane learns stays yours.",
            subtitle: "Your calibration and weather moments stay on this iPhone. No account and no personal profile to manage.",
            symbol: "hand.raised.fill",
            accent: VaneTheme.blue,
            isVisible: pageIsVisible
        ) {
            VStack(alignment: .leading, spacing: 17) {
                PrivacyLine(symbol: "iphone", text: "Personal learning stays on device")
                PrivacyLine(symbol: "person.crop.circle.badge.checkmark", text: "No account required")
                PrivacyLine(symbol: "arrow.counterclockwise", text: "Reset what Vane knows anytime")
            }
        }
    }

    private var isSkippable: Bool { (1...4).contains(page) }
    private var accentColor: Color {
        switch page {
        case 1, 4: VaneTheme.warm
        case 2: VaneTheme.cyan
        default: VaneTheme.blue
        }
    }
    private var primaryTitle: String {
        switch page {
        case 0: "Meet Vane"
        case pageCount - 1: "See my forecast"
        default: "Continue"
        }
    }
    private var locationStatus: String? {
        switch store.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: "Location is ready"
        case .denied, .restricted: "Location is off in Settings"
        default: nil
        }
    }
    private var locationActionTitle: String {
        switch store.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: "Location allowed"
        case .denied, .restricted: "Location unavailable"
        default: "Allow location"
        }
    }
    private var notificationStatus: String? {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Useful alerts are ready"
        case .denied: "Alerts are off in Settings"
        default: nil
        }
    }
    private var notificationActionTitle: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Alerts allowed"
        case .denied: "Alerts unavailable"
        default: "Allow useful alerts"
        }
    }
    private var temperaturePreferenceLabel: String {
        switch temperaturePreference {
        case ..<(-0.35): "I tend to feel cold"
        case 0.35...: "I tend to feel warm"
        default: "Mild feels about right"
        }
    }

    private func primaryAction() {
        if page == pageCount - 1 { finish() } else { move(to: page + 1) }
    }

    private func move(to destination: Int) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.12)) {
            page = min(max(destination, 0), pageCount - 1)
        }
    }

    private func selectWind(_ value: Double) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { windSensitivity = value }
    }

    private func finish() {
        let descriptor = FetchDescriptor<WeatherProfile>()
        if let profile = try? modelContext.fetch(descriptor).first {
            profile.temperaturePreference = temperaturePreference
            profile.windSensitivity = windSensitivity
        } else {
            modelContext.insert(WeatherProfile(temperaturePreference: temperaturePreference, windSensitivity: windSensitivity))
        }
        onComplete()
    }
}

private struct CalibrationPage<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color
    let isVisible: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 20)
            Image(systemName: symbol)
                .font(.system(size: 31, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 54, height: 54, alignment: .leading)
                .scaleEffect(isVisible ? 1 : 0.72)
                .opacity(isVisible ? 1 : 0)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .tracking(-1.3)
                    .foregroundStyle(VaneTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(VaneTheme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .offset(y: isVisible ? 0 : 12)
            .opacity(isVisible ? 1 : 0)

            content
                .padding(.vertical, 8)
                .offset(y: isVisible ? 0 : 20)
                .opacity(isVisible ? 1 : 0)
            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .animation(.spring(duration: 0.58, bounce: 0.16), value: isVisible)
    }
}

private struct PermissionPage: View {
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color
    let status: String?
    let actionTitle: String
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        CalibrationPage(title: title, subtitle: subtitle, symbol: symbol, accent: accent, isVisible: isVisible) {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: action) {
                    HStack {
                        Image(systemName: status == nil ? symbol : "checkmark.circle.fill")
                        Text(actionTitle)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.bold())
                    }
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .tint(accent)
                .vaneLiquidGlassButton(prominent: true)
                if let status {
                    Label(status, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VaneTheme.muted)
                        .transition(.blurReplace)
                }
            }
        }
    }
}

private struct ChoiceRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body.weight(.semibold))
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? VaneTheme.cyan : VaneTheme.muted.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
        .tint(isSelected ? VaneTheme.cyan : nil)
        .vaneLiquidGlassButton(prominent: isSelected)
        .foregroundStyle(VaneTheme.ink)
    }
}

private struct PrivacyLine: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(VaneTheme.ink)
    }
}
