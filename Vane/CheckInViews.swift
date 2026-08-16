import SwiftData
import SwiftUI

struct CheckInView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let snapshot: ForecastSnapshot
    var onSaved: (() -> Void)?
    @State private var response: FeelResponse?
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
                            Text(response == nil ? "How does it feel?" : "Anything making it feel different?")
                                .font(.largeTitle.bold())
                            Text(response == nil ? "Choose the closest match. There is no right answer." : "Optional context helps Sense separate temperature from the rest of the weather.")
                                .foregroundStyle(VaneTheme.muted)
                        }

                        if response == nil { responseChoices } else { contextChoices }
                    }
                    .padding(20)
                    .containerRelativeFrame(.horizontal)
                } }
            }
            .navigationTitle("Check In Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !didSave { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                if response != nil && !didSave {
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
                }
            }
            .alert("Check-in wasn’t saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") {}
            } message: { Text(saveError ?? "Please try again.") }
        }
    }

    private var responseChoices: some View {
        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(FeelResponse.allCases) { option in
                Button { withAnimation(.smooth) { response = option } } label: {
                    VStack(spacing: 10) {
                        Image(systemName: option.symbol).font(.title2)
                        Text(option.title).font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                }
                .vaneLiquidGlassButton(prominent: option == .comfortable)
                .accessibilityLabel("Feels \(option.title)")
            }
        }
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
        modelContext.insert(WeatherCheckIn(temperature: Double(current.temperature), apparentTemperature: Double(current.apparentTemperature), humidity: current.humidity, windSpeed: Double(current.windSpeed), response: response, context: contexts, dewPoint: Double(current.dewPoint), windGust: Double(current.windGust), uvIndex: current.uvIndex, cloudCover: current.cloudCover, isTravel: snapshot.isTravelLocation, precipitationKind: current.precipitationKind, precipitationChance: current.precipitationChance, timeZoneIdentifier: snapshot.timeZoneIdentifier, locationName: snapshot.locationName))
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
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnitPreference.fahrenheit.rawValue
    @AppStorage("windUnit") private var windUnitRaw = WindUnitPreference.milesPerHour.rawValue
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
                        .padding(.vertical, 5)
                    } else {
                        Label("Unreadable older check-in", systemImage: "exclamationmark.triangle").foregroundStyle(VaneTheme.muted)
                    }
                }
                .onDelete(perform: delete)
            }
        }
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
