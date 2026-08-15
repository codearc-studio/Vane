import CoreLocation
import Observation
import MapKit
import SwiftData
import SwiftUI

struct LocationsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\SavedPlace.sortOrder), SortDescriptor(\SavedPlace.createdAt)]) private var places: [SavedPlace]
    @Bindable var store: WeatherStore
    @State private var searchModel = PlaceSearchModel()
    @State private var query = ""
    @State private var appeared = false

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        locationHeader

                        Button { selectCurrentLocation() } label: {
                            LocationRow(
                                symbol: "location.fill",
                                title: "Use my current location",
                                subtitle: currentLocationSubtitle,
                                selected: store.isUsingCurrentLocation
                            )
                            .padding(.horizontal, 17)
                            .frame(maxWidth: .infinity, minHeight: 66)
                        }
                        .vaneLiquidGlassButton(prominent: store.isUsingCurrentLocation)

                        if !places.isEmpty {
                            locationSection(title: "Saved places") {
                                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                                    HStack(spacing: 8) {
                                        Button { select(place) } label: {
                                            LocationRow(
                                                symbol: "mappin.and.ellipse",
                                                title: place.name,
                                                subtitle: savedPlaceSubtitle(place),
                                                selected: isSelected(place)
                                            )
                                            .padding(.horizontal, 17)
                                            .frame(maxWidth: .infinity, minHeight: 64)
                                        }
                                        .vaneLiquidGlassButton(prominent: isSelected(place))

                                        Menu {
                                            if index > 0 { Button { move(place, to: index - 1) } label: { Label("Move up", systemImage: "arrow.up") } }
                                            if index < places.count - 1 { Button { move(place, to: index + 1) } label: { Label("Move down", systemImage: "arrow.down") } }
                                            Button(role: .destructive) { delete(place) } label: {
                                                Label("Remove \(place.name)", systemImage: "trash")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .font(.headline)
                                                .frame(width: 42, height: 42)
                                        }
                                        .vaneLiquidGlassButton()
                                        .accessibilityLabel("More options for \(place.name)")
                                    }
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        }

                        if hasQuery {
                            locationSection(title: "Search results") {
                                searchResults
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        } else if places.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "map.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(VaneTheme.blue)
                                Text("Save another place")
                                    .font(.headline)
                                Text("Search for a city, neighborhood or postal code. Vane will remember it here.")
                                    .font(.subheadline)
                                    .foregroundStyle(VaneTheme.muted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 44)
                    .containerRelativeFrame(.horizontal)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: reduceMotion || appeared ? 0 : 14)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "City, airport, code or postal code")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: query) {
                guard hasQuery else {
                    withAnimation { searchModel.results = [] }
                    return
                }
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                await searchModel.search(query)
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.12)) {
                    appeared = true
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.1), value: places.count)
            .animation(reduceMotion ? nil : .spring(duration: 0.42, bounce: 0.1), value: searchModel.results.count)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: searchModel.isSearching)
        }
    }

    private var locationHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionKicker(title: "Move with the weather")
            Text("Choose your sky.")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(-1)
            Text("Switch instantly, or search and save somewhere new.")
                .font(.subheadline)
                .foregroundStyle(VaneTheme.muted)
        }
        .foregroundStyle(VaneTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var searchResults: some View {
        if searchModel.isSearching {
            HStack(spacing: 10) {
                ProgressView()
                Text("Looking across the map…")
                    .font(.subheadline)
                    .foregroundStyle(VaneTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .transition(.opacity)
        } else if searchModel.results.isEmpty {
            ContentUnavailableView(
                "No places found",
                systemImage: "magnifyingglass",
                description: Text("Try a nearby city or postal code.")
            )
            .transition(.opacity)
        } else {
            ForEach(searchModel.results) { result in
                Button { saveAndSelect(result) } label: {
                    LocationRow(
                        symbol: "plus",
                        title: result.name,
                        subtitle: result.region,
                        selected: false
                    )
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity, minHeight: 64)
                }
                .vaneLiquidGlassButton()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func locationSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionKicker(title: title)
                .padding(.leading, 4)
            VStack(spacing: 9) {
                content()
            }
        }
    }

    private var currentLocationSubtitle: String {
        store.authorizationStatus == .denied || store.authorizationStatus == .restricted
            ? "Location permission is off in Settings"
            : store.isUsingCurrentLocation ? store.snapshot.locationName : "Follow this iPhone"
    }

    private func isSelected(_ place: SavedPlace) -> Bool {
        store.isSelected(place)
    }

    private func selectCurrentLocation() {
        store.requestCurrentLocation()
        dismiss()
    }

    private func select(_ place: SavedPlace) {
        Task { await store.loadSavedPlace(place) }
        dismiss()
    }

    private func saveAndSelect(_ result: PlaceSearchResult) {
        let existing = places.first {
            abs($0.latitude - result.latitude) < 0.01 && abs($0.longitude - result.longitude) < 0.01
        }
        let place = existing ?? SavedPlace(
            name: result.name,
            region: result.region,
            latitude: result.latitude,
            longitude: result.longitude
        )
        if existing == nil { modelContext.insert(place) }
        Task { await store.loadSavedPlace(place) }
        dismiss()
    }

    private func delete(_ place: SavedPlace) {
        let deletingSelection = store.isSelected(place)
        withAnimation(.spring(duration: 0.35, bounce: 0.08)) {
            modelContext.delete(place)
        }
        try? modelContext.save()
        if deletingSelection { store.resetSelection() }
    }

    private func move(_ place: SavedPlace, to destination: Int) {
        var reordered = places
        guard let source = reordered.firstIndex(where: { $0.id == place.id }) else { return }
        let item = reordered.remove(at: source)
        reordered.insert(item, at: min(max(destination, 0), reordered.count))
        for (index, place) in reordered.enumerated() { place.sortOrder = index }
        try? modelContext.save()
    }

    private func savedPlaceSubtitle(_ place: SavedPlace) -> String {
        if store.isSelected(place), !store.snapshot.isPlaceholder {
            return "\(store.snapshot.current.temperature.degrees) · \(store.snapshot.current.condition) · \(place.region)"
        }
        return place.region
    }
}

private struct LocationRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(selected ? .white : VaneTheme.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(selected ? .white.opacity(0.78) : VaneTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(selected ? .white : VaneTheme.ink)
        .contentShape(Rectangle())
    }
}

struct PlaceSearchResult: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
}

@MainActor
@Observable
final class PlaceSearchModel {
    var results: [PlaceSearchResult] = []
    var isSearching = false

    func search(_ query: String) async {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            guard let request = MKGeocodingRequest(addressString: cleaned) else { results = []; return }
            let items = try await request.mapItems
            guard !Task.isCancelled else { return }
            results = items.prefix(8).map { item in
                let name = item.addressRepresentations?.cityName ?? item.name ?? cleaned
                let region = item.addressRepresentations?.cityWithContext(.automatic)
                    ?? item.address?.shortAddress
                    ?? item.addressRepresentations?.regionName
                    ?? ""
                return PlaceSearchResult(
                    name: name,
                    region: region,
                    latitude: item.location.coordinate.latitude,
                    longitude: item.location.coordinate.longitude
                )
            }
        } catch is CancellationError {
            return
        } catch {
            results = []
        }
    }
}
