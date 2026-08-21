#if DEBUG
import SwiftUI
import WidgetKit

struct WidgetGalleryView: View {
    private let snapshot = VaneWidgetSnapshot.sample
    private var showsAccessoryPage: Bool { ProcessInfo.processInfo.environment["VANE_WIDGET_GALLERY_PAGE"] == "accessories" }
    private var showsLockScreenPage: Bool { ProcessInfo.processInfo.environment["VANE_WIDGET_GALLERY_PAGE"] == "lock" }

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.96, blue: 0.98).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    galleryHeader
                    if showsLockScreenPage {
                        lockScreenSection
                    } else if showsAccessoryPage {
                        widgetSection("SENSE") {
                            centeredTile(family: .systemMedium, kind: .sense, width: 338, height: 158)
                            centeredTile(family: .systemLarge, kind: .sense, width: 338, height: 354)
                        }
                        widgetSection("CONDITIONS & SUN") {
                            HStack(spacing: 18) {
                                tile(family: .systemSmall, kind: .details, width: 158, height: 158)
                                tile(family: .systemSmall, kind: .sun, width: 158, height: 158)
                            }
                            centeredTile(family: .systemMedium, kind: .details, width: 338, height: 158)
                            centeredTile(family: .systemMedium, kind: .sun, width: 338, height: 158)
                        }
                        lockScreenSection
                    } else {
                        widgetSection("SENSE") {
                            HStack(spacing: 18) {
                                tile(family: .systemSmall, kind: .sense, width: 158, height: 158)
                                tile(family: .systemSmall, kind: .now, width: 158, height: 158)
                            }
                            centeredTile(family: .systemMedium, kind: .sense, width: 338, height: 158)
                        }
                        widgetSection("NOW") {
                            centeredTile(family: .systemMedium, kind: .now, width: 338, height: 158)
                        }
                        widgetSection("FORECAST") {
                            centeredTile(family: .systemMedium, kind: .forecast, width: 338, height: 158)
                            centeredTile(family: .systemLarge, kind: .forecast, width: 338, height: 354)
                        }
                        widgetSection("CONDITIONS & SUN") {
                            HStack(spacing: 18) {
                                tile(family: .systemSmall, kind: .details, width: 158, height: 158)
                                tile(family: .systemSmall, kind: .sun, width: 158, height: 158)
                            }
                        }
                        lockScreenSection
                    }
                }
                .padding(22)
                .padding(.bottom, 30)
            }
        }
    }

    private var galleryHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Vane Widgets").font(.largeTitle.bold()).foregroundStyle(Color(red: 0.025, green: 0.075, blue: 0.14))
            Text("Home Screen, StandBy, Smart Stack and Lock Screen")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func widgetSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary)
            content()
        }
    }

    private func centeredTile(family: WidgetFamily, kind: VaneWidgetKind, width: CGFloat, height: CGFloat) -> some View {
        HStack { Spacer(); tile(family: family, kind: kind, width: width, height: height); Spacer() }
    }

    private func tile(family: WidgetFamily, kind: VaneWidgetKind, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if kind == .sense {
                VaneSenseWidgetBackground(snapshot: snapshot)
            } else {
                VaneWidgetBackground(snapshot: snapshot)
            }
            VaneWidgetContentView(family: family, kind: kind, snapshot: snapshot)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }

    private var lockScreenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOCK SCREEN").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary)
            VStack(spacing: 20) {
                VaneWidgetContentView(family: .accessoryInline, kind: .sense, snapshot: snapshot)
                    .frame(height: 26)
                HStack(spacing: 28) {
                    VaneWidgetContentView(family: .accessoryCircular, kind: .sense, snapshot: snapshot)
                        .frame(width: 62, height: 62)
                    VaneWidgetContentView(family: .accessoryCircular, kind: .sun, snapshot: snapshot)
                        .frame(width: 62, height: 62)
                    VaneWidgetContentView(family: .accessoryRectangular, kind: .sense, snapshot: snapshot)
                        .frame(width: 160, height: 62)
                }
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: .infinity)
            .background {
                LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.18, green: 0.26, blue: 0.39)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}
#endif
