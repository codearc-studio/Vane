import SwiftData
import SwiftUI

struct CheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let snapshot: ForecastSnapshot
    var onSaved: (() -> Void)?
    @State private var response: FeelResponse?
    @State private var contexts: Set<FeelContext> = []

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground(condition: snapshot.current)
                ScrollView {
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
                }
            }
            .navigationTitle("Check In Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if response != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
                }
            }
        }
    }

    private var responseChoices: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
        modelContext.insert(WeatherCheckIn(temperature: Double(current.temperature), apparentTemperature: Double(current.apparentTemperature), humidity: current.humidity, windSpeed: Double(current.windSpeed), response: response, context: contexts, dewPoint: Double(current.dewPoint), windGust: Double(current.windGust), uvIndex: current.uvIndex, cloudCover: current.cloudCover, isTravel: snapshot.sourceID != "current"))
        do { try modelContext.save() } catch { return }
        onSaved?()
        dismiss()
    }
}

struct CheckInHistoryView: View {
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
                                Text(checkIn.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(VaneTheme.muted)
                            }
                            Text("\(Int(checkIn.apparentTemperature.rounded()))° apparent · \(Int(checkIn.windSpeed.rounded())) mph wind · \(checkIn.humidity.formatted(.percent.precision(.fractionLength(0)))) humidity")
                                .font(.caption).foregroundStyle(VaneTheme.muted)
                            if !checkIn.contexts.isEmpty {
                                Text(checkIn.contexts.map(\.title).sorted().joined(separator: " · ")).font(.caption2).foregroundStyle(VaneTheme.blue)
                            }
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
