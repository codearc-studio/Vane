import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Bindable var store: WeatherStore
    @Bindable var notifications: NotificationManager
    @State private var page = Int(ProcessInfo.processInfo.environment["VANE_ONBOARDING_PAGE"] ?? "") ?? 0
    @State private var temperaturePreference: Double?
    @State private var windSensitivity: Double?
    @State private var showLocations = false
    let onComplete: () -> Void
    private let pageCount = 5

    var body: some View {
        GeometryReader { viewport in
            ZStack {
                AtmosphericBackground()
                VStack(spacing: 0) {
                    HStack { if page > 0 { Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Back") }; Spacer() }.padding(.horizontal, 20).padding(.top, 8)
                    TabView(selection: $page) {
                        welcome.frame(width: viewport.size.width).tag(0)
                        temperature.frame(width: viewport.size.width).tag(1)
                        wind.frame(width: viewport.size.width).tag(2)
                        location.frame(width: viewport.size.width).tag(3)
                        ready.frame(width: viewport.size.width).tag(4)
                    }.tabViewStyle(.page(indexDisplayMode: .never)).animation(reduceMotion ? nil : .smooth, value: page)
                    controls
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
        }
        .tint(VaneTheme.blue)
        .sheet(isPresented: $showLocations) { LocationsView(store: store) }
    }

    private var welcome: some View {
        GeometryReader { geometry in
            VStack(spacing: 24) {
                Spacer(); VaneMark(size: 160).shadow(color: VaneTheme.blue.opacity(0.15), radius: 24, y: 12)
                Text("Weather, the way\nit feels to you.").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("Sense learns from occasional, optional check-ins. It starts gently, improves over time, and never pretends to know more than you have taught it.").font(.title3).foregroundStyle(VaneTheme.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(width: max(geometry.size.width - 48, 0))
                Spacer()
            }
            .frame(width: geometry.size.width)
        }
    }

    private var temperature: some View {
        OnboardingPage(title: "Which sounds most like you?", subtitle: "This is only a starting point. Choose Not sure if none feels right.", symbol: "thermometer.medium") {
            choice("I usually want more warmth", selected: temperaturePreference == -0.7) { temperaturePreference = -0.7 }
            choice("Mild weather feels about right", selected: temperaturePreference == 0) { temperaturePreference = 0 }
            choice("I usually want less warmth", selected: temperaturePreference == 0.7) { temperaturePreference = 0.7 }
            choice("Not sure — learn as I go", selected: temperaturePreference == nil) { temperaturePreference = nil }
        }
    }

    private var wind: some View {
        OnboardingPage(title: "How much does wind change things?", subtitle: "A breezy day can land differently, but you do not need to define a sensitivity now.", symbol: "wind") {
            choice("I notice it quickly", selected: windSensitivity == 1) { windSensitivity = 1 }
            choice("It depends", selected: windSensitivity == 0.5) { windSensitivity = 0.5 }
            choice("It rarely changes the feel", selected: windSensitivity == 0) { windSensitivity = 0 }
            choice("Not sure — learn as I go", selected: windSensitivity == nil) { windSensitivity = nil }
        }
    }

    private var location: some View {
        OnboardingPage(title: "Where should weather begin?", subtitle: "Use your location for a live local forecast, or choose any place manually.", symbol: "location.fill") {
            Button { locationAction() } label: { Label(locationTitle, systemImage: store.authorizationStatus == .denied || store.authorizationStatus == .restricted ? "gear" : "location.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 54) }.vaneLiquidGlassButton(prominent: true)
            Button { showLocations = true } label: { Label("Choose a Location", systemImage: "map.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 54) }.vaneLiquidGlassButton()
            if store.authorizationStatus == .authorizedAlways || store.authorizationStatus == .authorizedWhenInUse { Label("Location is ready", systemImage: "checkmark.circle.fill").foregroundStyle(VaneTheme.blue).font(.subheadline) }
        }
    }

    private var ready: some View {
        OnboardingPage(title: "Vane is ready.", subtitle: "Personal learning is stored privately on this device today. No account is required, and you can reset what Sense knows anytime.", symbol: "hand.raised.fill") {
            info("iphone", "Personal learning stays on device")
            info("person.crop.circle.badge.checkmark", "No account required")
            info("bell.slash", "Notification permission is asked only when you enable an alert")
            info("arrow.counterclockwise", "Reset what Sense knows anytime")
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) { ForEach(0..<pageCount, id: \.self) { index in Capsule().fill(index == page ? VaneTheme.blue : VaneTheme.ink.opacity(0.16)).frame(width: index == page ? 24 : 7, height: 7) } }
            HStack(spacing: 12) {
                if (1...3).contains(page) { Button("Skip") { move(1) }.font(.headline).frame(maxWidth: .infinity, minHeight: 54).vaneLiquidGlassButton() }
                Button(page == pageCount - 1 ? "See my weather" : page == 0 ? "Meet Sense" : "Continue") { page == pageCount - 1 ? finish() : move(1) }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 54).vaneLiquidGlassButton(prominent: true)
            }
        }.padding(20)
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(title).font(.headline); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle") }.padding(.horizontal, 17).frame(minHeight: 56) }.vaneLiquidGlassButton(prominent: selected)
    }
    private func info(_ symbol: String, _ text: String) -> some View { Label(text, systemImage: symbol).font(.headline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
    private var locationTitle: String { store.authorizationStatus == .denied || store.authorizationStatus == .restricted ? "Open Settings" : "Use My Location" }
    private func locationAction() { if store.authorizationStatus == .denied || store.authorizationStatus == .restricted { store.openLocationSettings() } else { store.requestCurrentLocation() } }
    private func move(_ delta: Int) { withAnimation(reduceMotion ? nil : .smooth) { page = min(max(page + delta, 0), pageCount - 1) } }
    private func finish() {
        let descriptor = FetchDescriptor<WeatherProfile>(sortBy: [SortDescriptor(\.createdAt)])
        let profile = (try? modelContext.fetch(descriptor).first) ?? WeatherProfile()
        if profile.modelContext == nil { modelContext.insert(profile) }
        profile.temperaturePreference = temperaturePreference ?? 0
        profile.windSensitivity = windSensitivity ?? 0.5
        try? modelContext.save()
        onComplete()
    }
}

private struct OnboardingPage<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: Content
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer(minLength: 34)
                    Image(systemName: symbol).font(.largeTitle).foregroundStyle(VaneTheme.blue).frame(width: 54, height: 54)
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).font(.body).foregroundStyle(VaneTheme.muted)
                    VStack(spacing: 12) { content }
                    Spacer(minLength: 20)
                }
                .frame(width: max(geometry.size.width - 44, 0), alignment: .leading)
                .padding(.horizontal, 22)
            }
            .frame(width: geometry.size.width)
        }
    }
}
