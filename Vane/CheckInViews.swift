import SwiftData
import SwiftUI

struct CheckInView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let snapshot: ForecastSnapshot
    var onSaved: (() -> Void)?
    @State private var response: FeelResponse?
    @State private var feelValue = 3.0
    @State private var hasChosenFeeling = false
    @State private var isDraggingFeeling = false
    @State private var isChoosingContext = false
    @State private var contexts: Set<FeelContext> = []
    @State private var didSave = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground(condition: snapshot.current)
                if didSave {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 68))
                            .foregroundStyle(VaneTheme.blue)
                            .symbolEffect(.bounce)
                        Text("Check-in saved")
                            .font(.largeTitle.bold())
                        Text("This moment now helps Sense understand how \(snapshot.locationName)’s weather felt to you.")
                            .foregroundStyle(VaneTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                } else { ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionKicker(title: snapshot.locationName)
                            Text(isChoosingContext ? "Anything making it feel different?" : "How does it feel?")
                                .font(.largeTitle.bold())
                            Text(isChoosingContext ? "Optional context helps Sense separate temperature from the rest of the weather." : "Drag the scale or use a quick pick. There is no right answer.")
                                .foregroundStyle(VaneTheme.muted)
                        }

                        if isChoosingContext { contextChoices } else { responseChoices }
                    }
                    .padding(20)
                    .containerRelativeFrame(.horizontal)
                } }
            }
            .navigationTitle("Check In Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !didSave { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                if isChoosingContext && !didSave {
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
                }
            }
            .alert("Check-in wasn’t saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") {}
            } message: { Text(saveError ?? "Please try again.") }
        }
    }

    private var responseChoices: some View {
        VStack(spacing: 20) {
            GlassCard {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: response?.symbol ?? "hand.draw.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(hasChosenFeeling ? VaneTheme.blue : VaneTheme.muted)
                            .contentTransition(.symbolEffect(.replace))
                        Text(response?.title ?? "Slide to choose")
                            .font(.title2.bold())
                            .contentTransition(.numericText())
                    }

                    feelingScale

                    HStack {
                        Label("Freezing", systemImage: "snowflake")
                        Spacer()
                        Text("Comfortable")
                        Spacer()
                        Label("Very hot", systemImage: "sun.max.fill")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(VaneTheme.muted)
                    .labelStyle(.titleOnly)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("QUICK PICKS")
                            .font(.caption2.bold())
                            .tracking(1)
                            .foregroundStyle(VaneTheme.muted)
                        HStack(spacing: 8) {
                            feelingPreset(.cold)
                            feelingPreset(.comfortable)
                            feelingPreset(.hot)
                        }
                    }
                }
                .padding(22)
            }

            Button {
                guard hasChosenFeeling else { return }
                withAnimation(.smooth) { isChoosingContext = true }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .vaneLiquidGlassButton(prominent: hasChosenFeeling)
            .disabled(!hasChosenFeeling)
        }
    }

    private var feelingScale: some View {
        GeometryReader { geometry in
            let inset = 16.0
            let thumbSize = 32.0
            let trackWidth = max(1, geometry.size.width - (inset * 2))
            let maximum = Double(FeelResponse.allCases.count - 1)
            let thumbCenter = inset + ((feelValue / maximum) * trackWidth)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.82), VaneTheme.blue.opacity(0.58), Color.mint.opacity(0.72), Color.orange.opacity(0.78), Color.red.opacity(0.78)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
                    .padding(.horizontal, inset)

                HStack(spacing: 0) {
                    ForEach(FeelResponse.allCases) { option in
                        Circle()
                            .fill(.white.opacity(option == response ? 1 : 0.66))
                            .frame(width: 5, height: 5)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, inset - 2)

                if hasChosenFeeling {
                    Circle()
                        .fill(.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(Circle().stroke(VaneTheme.blue.opacity(0.28), lineWidth: 1))
                        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                        .offset(x: thumbCenter - (thumbSize / 2))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingFeeling = true
                        let position = min(max(value.location.x - inset, 0), trackWidth)
                        updateFeeling((position / trackWidth) * maximum)
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.16)) { isDraggingFeeling = false }
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("How the weather feels")
        .accessibilityValue(response?.title ?? "Not chosen")
        .accessibilityHint("Swipe up or down to choose a feeling")
        .accessibilityAdjustableAction { direction in
            let current = hasChosenFeeling ? Int(feelValue.rounded()) : FeelResponse.allCases.count / 2
            switch direction {
            case .increment: chooseFeeling(min(current + (hasChosenFeeling ? 1 : 0), FeelResponse.allCases.count - 1))
            case .decrement: chooseFeeling(max(current - (hasChosenFeeling ? 1 : 0), 0))
            @unknown default: break
            }
        }
    }

    private func chooseFeeling(_ index: Int) {
        let boundedIndex = min(max(index, 0), FeelResponse.allCases.count - 1)
        feelValue = Double(boundedIndex)
        response = FeelResponse.allCases[boundedIndex]
        revealFeelingIfNeeded()
    }

    private func updateFeeling(_ value: Double) {
        let maximum = Double(FeelResponse.allCases.count - 1)
        let boundedValue = min(max(value, 0), maximum)
        feelValue = boundedValue
        response = FeelResponse.allCases[Int(boundedValue.rounded())]
        revealFeelingIfNeeded()
    }

    private func revealFeelingIfNeeded() {
        if !hasChosenFeeling {
            withAnimation(.spring(duration: 0.24, bounce: 0.16)) { hasChosenFeeling = true }
        }
    }

    private func feelingPreset(_ option: FeelResponse) -> some View {
        let isSelected = response == option && !isDraggingFeeling
        return Button {
            guard let index = FeelResponse.allCases.firstIndex(of: option) else { return }
            withAnimation(.spring(duration: 0.28, bounce: 0.16)) { chooseFeeling(index) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: option.symbol)
                    .font(.headline)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: response == option)
                Text(option.title)
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(isSelected ? .white : VaneTheme.ink)
            .background(isSelected ? VaneTheme.blue : VaneTheme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose \(option.title)")
    }

    private var contextChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(FeelContext.allCases) { context in
                Button { toggle(context) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: context.symbol).frame(width: 28)
                        Text(context.title).font(.headline)
                        Spacer()
                        Image(systemName: contexts.contains(context) ? "checkmark.circle.fill" : "circle")
                    }
                    .padding(.horizontal, 18)
                    .frame(minHeight: 56)
                }
                .vaneLiquidGlassButton(prominent: contexts.contains(context))
            }
            Button("Skip and save") { save() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.top, 8)
        }
    }

    private func toggle(_ context: FeelContext) {
        if context == .nothing {
            contexts = contexts.contains(.nothing) ? [] : [.nothing]
        } else {
            contexts.remove(.nothing)
            if contexts.contains(context) { contexts.remove(context) } else { contexts.insert(context) }
        }
    }

    private func save() {
        guard let response else { return }
        let current = snapshot.current
        modelContext.insert(WeatherCheckIn(temperature: Double(current.temperature), apparentTemperature: Double(current.apparentTemperature), humidity: current.humidity, windSpeed: Double(current.windSpeed), response: response, context: contexts, dewPoint: Double(current.dewPoint), windGust: Double(current.windGust), uvIndex: current.uvIndex, cloudCover: current.cloudCover, pressure: current.pressure, visibility: current.visibility, isDaylight: current.isDaylight, isTravel: snapshot.isTravelLocation, precipitationKind: current.precipitationKind, precipitationChance: current.precipitationChance, timeZoneIdentifier: snapshot.timeZoneIdentifier, locationName: snapshot.locationName))
        do { try modelContext.save() } catch { saveError = "Vane couldn’t save this moment. Please try again."; return }
        onSaved?()
        withAnimation(.spring(duration: 0.45, bounce: 0.16)) { didSave = true }
        Task {
            try? await Task.sleep(for: .seconds(1.35))
            dismiss()
        }
    }
}

struct CheckInHistoryView: View {
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnitPreference.localizedDefault.rawValue
    @AppStorage("windUnit") private var windUnitRaw = WindUnitPreference.localizedDefault.rawValue
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeatherCheckIn.createdAt, order: .reverse) private var checkIns: [WeatherCheckIn]

    var body: some View {
        List {
            if checkIns.isEmpty {
                ContentUnavailableView("No check-ins yet", systemImage: "checkmark.bubble", description: Text("Your weather moments will appear here."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(checkIns) { checkIn in
                    if let response = checkIn.feelResponse {
                        GlassCard(radius: 22, tint: VaneTheme.blue.opacity(0.045)) {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Label(response.title, systemImage: response.symbol).font(.headline)
                                    Spacer()
                                    Text(recordFormatting(checkIn).shortDateTime(checkIn.createdAt)).font(.caption).foregroundStyle(VaneTheme.muted)
                                }
                                Text("Feels Like \(formatting.degrees(checkIn.apparentTemperature, includeUnit: true)) · \(formatting.windSpeed(Int(checkIn.windSpeed.rounded()))) wind · \(checkIn.humidity.formatted(.percent.precision(.fractionLength(0)))) humidity")
                                    .font(.caption).foregroundStyle(VaneTheme.muted)
                                if !checkIn.contexts.isEmpty {
                                    Text(checkIn.contexts.map(\.title).sorted().joined(separator: " · ")).font(.caption2).foregroundStyle(VaneTheme.blue)
                                }
                                if let locationName = checkIn.locationName { Text(locationName).font(.caption2).foregroundStyle(VaneTheme.muted) }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        GlassCard(radius: 22) {
                            Label("Unreadable older check-in", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(VaneTheme.muted)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .onDelete(perform: delete)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 18))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AtmosphericBackground())
        .navigationTitle("Check-in History")
        .toolbar { if !checkIns.isEmpty { EditButton() } }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(checkIns[index]) }
        try? modelContext.save()
    }

    private var formatting: WeatherFormatting { WeatherFormatting(temperature: TemperatureUnitPreference(rawValue: temperatureUnitRaw) ?? .fahrenheit, wind: WindUnitPreference(rawValue: windUnitRaw) ?? .milesPerHour) }
    private func recordFormatting(_ checkIn: WeatherCheckIn) -> WeatherFormatting { WeatherFormatting(temperature: TemperatureUnitPreference(rawValue: temperatureUnitRaw) ?? .fahrenheit, wind: WindUnitPreference(rawValue: windUnitRaw) ?? .milesPerHour, timeZone: checkIn.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current) }
}

enum DataCoordinator {
    @MainActor
    static func prepare(context: ModelContext) {
        let descriptor = FetchDescriptor<WeatherProfile>(sortBy: [SortDescriptor(\.createdAt)])
        let profiles = (try? context.fetch(descriptor)) ?? []
        if profiles.isEmpty { context.insert(WeatherProfile()) }
        if profiles.count > 1 {
            for duplicate in profiles.dropFirst() { context.delete(duplicate) }
        }
        let checkIns = (try? context.fetch(FetchDescriptor<WeatherCheckIn>())) ?? []
        for checkIn in checkIns {
            if let decoded = checkIn.feelResponse, checkIn.response != decoded.rawValue { checkIn.response = decoded.rawValue }
        }
        try? context.save()
    }
}
