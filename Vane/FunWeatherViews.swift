import SwiftUI
import UIKit

extension WeatherMoodStyle {
    var colors: [Color] {
        switch self {
        case .sunshine: [Color(red: 1.0, green: 0.78, blue: 0.32), Color(red: 0.98, green: 0.48, blue: 0.28)]
        case .fresh: [VaneTheme.cyan, VaneTheme.blue]
        case .cozy: [Color(red: 0.48, green: 0.57, blue: 0.72), Color(red: 0.28, green: 0.37, blue: 0.55)]
        case .electric: [Color(red: 0.44, green: 0.35, blue: 0.82), Color(red: 0.16, green: 0.22, blue: 0.44)]
        case .crisp: [Color(red: 0.48, green: 0.80, blue: 0.95), Color(red: 0.28, green: 0.52, blue: 0.86)]
        case .night: [Color(red: 0.15, green: 0.20, blue: 0.40), Color(red: 0.04, green: 0.08, blue: 0.18)]
        }
    }
}

struct TodayWeatherCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let experience: DayWeatherExperience
    let formatting: WeatherFormatting
    let onOpen: () -> Void
    let onShare: () -> Void

    private var topActivity: WeatherActivityRecommendation? { experience.activities.first }

    var body: some View {
        GlassCard(radius: 34, tint: experience.mood.style.colors.first?.opacity(0.12)) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(experience.mood.style.colors.first?.opacity(0.20) ?? .clear)
                    .frame(width: 190, height: 190)
                    .blur(radius: 45)
                    .offset(x: 70, y: -92)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(LinearGradient(colors: experience.mood.style.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(.white.opacity(0.42), lineWidth: 0.75)
                            Image(systemName: experience.mood.symbolName)
                                .font(.system(size: 29, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white)
                        }
                        .frame(width: 62, height: 62)
                        .shadow(color: experience.mood.style.colors.last?.opacity(0.26) ?? .clear, radius: 14, y: 8)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            SectionKicker(title: "Today, in a word")
                            Text(experience.mood.title)
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                            Text(experience.mood.detail)
                                .font(.subheadline)
                                .foregroundStyle(VaneTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { scoreBlock; topPickBlock }
                        VStack(alignment: .leading, spacing: 10) { scoreBlock; topPickBlock }
                    }

                    HStack(spacing: 10) {
                        Button(action: onOpen) {
                            Label("Explore today", systemImage: "sparkles")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .vaneLiquidGlassButton(prominent: true)

                        Button(action: onShare) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline)
                                .frame(width: 48, height: 48)
                        }
                        .vaneLiquidGlassButton()
                        .accessibilityLabel("Share today’s weather card")
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreBlock: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.30), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: Double(experience.outdoorScore) / 100)
                    .stroke(LinearGradient(colors: experience.mood.style.colors, startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(experience.outdoorScore)")
                    .font(.subheadline.bold().monospacedDigit())
            }
            .frame(width: 54, height: 54)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Outdoor score")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VaneTheme.muted)
                Text(experience.outdoorLabel)
                    .font(.headline)
                Text(experience.isPersonalized ? "Shaped by Sense" : "Weather-based")
                    .font(.caption2)
                    .foregroundStyle(VaneTheme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 0.6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Outdoor score, \(experience.outdoorScore) out of 100, \(experience.outdoorLabel)")
    }

    private var topPickBlock: some View {
        HStack(spacing: 11) {
            Image(systemName: topActivity?.kind.symbolName ?? "figure.walk")
                .font(.title3)
                .foregroundStyle(experience.mood.style.colors.last ?? VaneTheme.blue)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.30), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Top pick")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VaneTheme.muted)
                Text(topActivity?.kind.title ?? "Keep it flexible")
                    .font(.headline)
                Text(topActivity.map(bestWindowText) ?? "No clear window")
                    .font(.caption2)
                    .foregroundStyle(VaneTheme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 0.6))
    }

    private func bestWindowText(_ activity: WeatherActivityRecommendation) -> String {
        guard let start = activity.bestStart else { return "Conditions right now" }
        guard let end = activity.bestEnd else { return "Around \(formatting.shortTime(start))" }
        return "\(formatting.shortTime(start))–\(formatting.shortTime(end))"
    }
}

struct DayWeatherExperienceView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: ForecastSnapshot
    let experience: DayWeatherExperience
    let formatting: WeatherFormatting
    let onShare: () -> Void

    var body: some View {
        ZStack {
            AtmosphericBackground(condition: snapshot.current)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    moodHero
                    outdoorRead
                    activities
                    if let moment = experience.seasonalMoment { seasonalMoment(moment) }
                    methodology
                }
                .padding(18)
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 130 : 50)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Today’s ideas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share today’s weather card")
            }
        }
    }

    private var moodHero: some View {
        GlassCard(radius: 34, dark: true, tint: experience.mood.style.colors.first?.opacity(0.22)) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: experience.mood.style.colors.map { $0.opacity(0.84) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 230, height: 230)
                    .blur(radius: 34)
                    .offset(x: 105, y: -100)
                Image(systemName: experience.mood.symbolName)
                    .font(.system(size: 176, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.075))
                    .offset(x: 42, y: 48)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        HStack(spacing: 8) {
                            VaneMark(size: 38)
                                .brightness(3)
                            Text("VANE")
                                .font(.caption.bold())
                                .tracking(1.2)
                        }
                        Spacer()
                        Label(snapshot.locationName, systemImage: "location.fill")
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.78))

                    Spacer(minLength: 8)

                    HStack(alignment: .bottom, spacing: 14) {
                        Image(systemName: experience.mood.symbolName)
                            .font(.system(size: 47, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .frame(width: 68, height: 68)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 0.75))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            SectionKicker(title: "Today, in a word", dark: true)
                            Text(experience.mood.title)
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .minimumScaleFactor(0.76)
                                .lineLimit(2)
                            Text(experience.mood.detail)
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                }
                .padding(22)
            }
            .frame(maxWidth: .infinity, minHeight: 284, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    private var outdoorRead: some View {
        GlassCard(tint: experience.mood.style.colors.first?.opacity(0.07)) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(VaneTheme.blue.opacity(0.10), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: Double(experience.outdoorScore) / 100)
                        .stroke(
                            LinearGradient(colors: experience.mood.style.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(experience.outdoorScore)")
                            .font(.title2.bold().monospacedDigit())
                        Text("/100").font(.caption2.bold()).foregroundStyle(VaneTheme.muted)
                    }
                }
                .frame(width: 92, height: 92)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    SectionKicker(title: "Outdoor score")
                    Text(experience.outdoorLabel)
                        .font(.title2.bold())
                    Text(experience.outdoorDetail)
                        .font(.subheadline)
                        .foregroundStyle(VaneTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Outdoor score, \(experience.outdoorScore) out of 100. \(experience.outdoorLabel). \(experience.outdoorDetail)")
    }

    private var activities: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionKicker(title: "Plans & activities")
                Text("Best fits for today")
                    .font(.title2.bold())
                Text("Ranked by the best remaining daylight window.")
                    .font(.subheadline)
                    .foregroundStyle(VaneTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(experience.activities) { activity in
                GlassCard(radius: 24, tint: VaneTheme.blue.opacity(0.045)) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: activity.kind.symbolName)
                            .font(.title2)
                            .foregroundStyle(VaneTheme.blue)
                            .frame(width: 46, height: 46)
                            .background(VaneTheme.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(activity.kind.title).font(.headline)
                                Spacer()
                                Text(activityLabel(activity.score))
                                    .font(.caption.bold())
                                    .foregroundStyle(VaneTheme.blue)
                            }
                            Text(windowText(activity))
                                .font(.caption.bold())
                            Text(activity.reason)
                                .font(.caption)
                                .foregroundStyle(VaneTheme.muted)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seasonalMoment(_ moment: SeasonalWeatherMoment) -> some View {
        GlassCard(radius: 24, tint: VaneTheme.warm.opacity(0.08)) {
            HStack(spacing: 14) {
                Image(systemName: moment.symbolName)
                    .font(.title2)
                    .foregroundStyle(VaneTheme.warm)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.26), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    SectionKicker(title: "Seasonal moment")
                    Text(moment.title).font(.headline)
                    Text(moment.detail).font(.caption).foregroundStyle(VaneTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var methodology: some View {
        Label(
            experience.isPersonalized
                ? "Scores combine the forecast with your learned comfort range. They are planning estimates, and official weather alerts always take priority."
                : "Scores use temperature, rain chance, humidity, wind, and daylight. They are planning estimates, and official weather alerts always take priority.",
            systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(VaneTheme.muted)
    }

    private func windowText(_ activity: WeatherActivityRecommendation) -> String {
        guard let start = activity.bestStart else { return "Current conditions" }
        if let end = activity.bestEnd { return "Best window · \(formatting.shortTime(start))–\(formatting.shortTime(end))" }
        return "Best around \(formatting.shortTime(start))"
    }

    private func activityLabel(_ score: Int) -> String {
        switch score {
        case 82...: "GREAT FIT"
        case 66...: "GOOD FIT"
        case 46...: "POSSIBLE"
        default: "SKIP FOR NOW"
        }
    }
}

struct WeatherPersonalityCard: View {
    let personality: WeatherPersonality?

    var body: some View {
        GlassCard(radius: 30, tint: VaneTheme.cyan.opacity(0.10)) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(VaneTheme.cyan.opacity(0.15))
                    .frame(width: 150, height: 150)
                    .blur(radius: 34)
                    .offset(x: 55, y: -72)
                    .accessibilityHidden(true)

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .fill(LinearGradient(colors: [VaneTheme.cyan, VaneTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .stroke(.white.opacity(0.42), lineWidth: 0.75)
                        Image(systemName: personality?.symbolName ?? "sparkles")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 64, height: 64)
                    .shadow(color: VaneTheme.blue.opacity(0.20), radius: 14, y: 8)

                    VStack(alignment: .leading, spacing: 5) {
                        SectionKicker(title: "Your weather style")
                        Text(personality?.title ?? "Still taking shape")
                            .font(.title3.bold())
                        Text(personality?.detail ?? "A few varied check-ins will reveal the kinds of weather that feel most like you.")
                            .font(.subheadline)
                            .foregroundStyle(VaneTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(19)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct WeatherShareCard: View {
    let snapshot: ForecastSnapshot
    let experience: DayWeatherExperience
    let formatting: WeatherFormatting

    var body: some View {
        ZStack {
            LinearGradient(colors: experience.mood.style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 310, height: 310)
                .blur(radius: 20)
                .offset(x: 160, y: -210)
            Circle()
                .fill(.black.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 40)
                .offset(x: -155, y: 240)
            VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VaneMark(size: 46)
                            .brightness(3)
                        Text("Vane")
                            .font(.title3.bold())
                        Spacer()
                        Label(snapshot.locationName, systemImage: "location.fill")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: experience.mood.symbolName)
                        .font(.system(size: 54, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text(experience.mood.title)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.75)
                        .lineLimit(2)
                    Text(experience.mood.detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.76))
                        .padding(.top, 5)
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatting.degrees(snapshot.current.temperature))
                                .font(.system(size: 70, weight: .thin, design: .rounded))
                            Text(snapshot.current.condition)
                                .font(.headline)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(experience.outdoorScore)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                            Text("OUTDOOR · \(experience.outdoorLabel.uppercased())")
                                .font(.caption2.bold())
                                .tracking(0.7)
                        }
                    }
                    if let activity = experience.activities.first {
                        Divider().overlay(.white.opacity(0.24)).padding(.vertical, 14)
                        Label("Top pick · \(activity.kind.title)", systemImage: activity.kind.symbolName)
                            .font(.subheadline.bold())
                    }
            }
            .padding(26)
        }
        .foregroundStyle(.white)
        .frame(width: 360, height: 450)
        .overlay { Rectangle().stroke(.white.opacity(0.24), lineWidth: 1) }
    }
}

struct WeatherSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let caption: String
}

struct WeatherActivitySheet: UIViewControllerRepresentable {
    let payload: WeatherSharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [payload.image, payload.caption], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
