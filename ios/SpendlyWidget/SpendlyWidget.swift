import WidgetKit
import SwiftUI

// MARK: - Shared data

/// App Group id — must match Runner.entitlements, SpendlyWidget.entitlements,
/// and the Dart `widgetAppGroupId`.
private let appGroupId = "group.com.spendly.spendly"

private let indigo = Color(red: 0.39, green: 0.40, blue: 0.95) // #6366F1
private let pink = Color(red: 0.93, green: 0.28, blue: 0.60)   // #EC4899
private let brandGradient = LinearGradient(
    colors: [indigo, pink], startPoint: .topLeading, endPoint: .bottomTrailing)

struct TrendBar: Decodable { let label: String; let heightPct: Int }
struct QuickCategory: Decodable { let id: Int; let icon: String; let name: String }

/// Snapshot read from the App Group UserDefaults (written by the Flutter app via
/// home_widget). Missing store → safe zeros, so a fresh widget renders blankly
/// rather than crashing.
struct Snapshot {
    let todayTotal: String
    let monthTotal: String
    let budgetPct: Int
    let budgetLeft: String
    let hasBudget: Bool
    let trend: [TrendBar]
    let quickAdd: [QuickCategory]

    static func load() -> Snapshot {
        let d = UserDefaults(suiteName: appGroupId)
        func str(_ k: String, _ fallback: String = "—") -> String { d?.string(forKey: k) ?? fallback }
        func decode<T: Decodable>(_ k: String, _ type: T.Type) -> T? {
            guard let s = d?.string(forKey: k), let data = s.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return Snapshot(
            todayTotal: str("todayTotal", "₹0"),
            monthTotal: str("monthTotal", "₹0"),
            budgetPct: Int(str("budgetPct", "0")) ?? 0,
            budgetLeft: str("budgetLeft", ""),
            hasBudget: str("hasBudget", "false") == "true",
            trend: decode("trend", [TrendBar].self) ?? [],
            quickAdd: decode("quickAdd", [QuickCategory].self) ?? []
        )
    }
}

// MARK: - Timeline

struct SpendlyEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SpendlyEntry {
        SpendlyEntry(date: Date(), snapshot: Snapshot.load())
    }
    func getSnapshot(in context: Context, completion: @escaping (SpendlyEntry) -> Void) {
        completion(SpendlyEntry(date: Date(), snapshot: Snapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendlyEntry>) -> Void) {
        // The app pushes fresh data via reloadTimelines after every write, so a
        // single entry is enough; refresh again in an hour as a safety net.
        let entry = SpendlyEntry(date: Date(), snapshot: Snapshot.load())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Small pieces

private func miniBars(_ trend: [TrendBar]) -> some View {
    HStack(alignment: .bottom, spacing: 4) {
        ForEach(Array(trend.enumerated()), id: \.offset) { _, bar in
            RoundedRectangle(cornerRadius: 2)
                .fill(bar.heightPct >= 100 || bar.label == trend.last?.label ? Color.white : Color.white.opacity(0.5))
                .frame(height: max(3, CGFloat(bar.heightPct) * 0.4))
        }
    }
    .frame(height: 40, alignment: .bottom)
}

// MARK: - Widget views

struct TodayView: View {
    let snapshot: Snapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY").font(.system(size: 11, weight: .semibold)).opacity(0.85)
            Text(snapshot.todayTotal).font(.system(size: 24, weight: .bold))
            Spacer()
            miniBars(snapshot.trend)
        }
        .padding(16)
        .foregroundColor(.white)
        .containerBackgroundCompat(brandGradient)
    }
}

struct QuickAddView: View {
    let snapshot: Snapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK ADD").font(.system(size: 11, weight: .semibold)).opacity(0.85)
            let cats = Array(snapshot.quickAdd.prefix(4))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(cats, id: \.id) { cat in
                    Link(destination: URL(string: "spendly://quickadd?category=\(cat.id)")!) {
                        Text(cat.icon).font(.system(size: 22))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(Color.white.opacity(0.18))
                            .cornerRadius(11)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .foregroundColor(.white)
        .containerBackgroundCompat(brandGradient)
    }
}

struct MonthView: View {
    let snapshot: Snapshot
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("THIS MONTH").font(.system(size: 11, weight: .semibold)).opacity(0.85)
                Text(snapshot.monthTotal).font(.system(size: 26, weight: .bold))
                if snapshot.hasBudget {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.25)).frame(height: 6)
                            Capsule().fill(Color.white)
                                .frame(width: geo.size.width * CGFloat(snapshot.budgetPct) / 100.0, height: 6)
                        }
                    }.frame(height: 6)
                    Text("\(snapshot.budgetPct)% used · \(snapshot.budgetLeft) left")
                        .font(.system(size: 11)).opacity(0.85)
                }
                Spacer()
                HStack(spacing: 8) {
                    ForEach(Array(snapshot.quickAdd.prefix(4)), id: \.id) { cat in
                        Link(destination: URL(string: "spendly://quickadd?category=\(cat.id)")!) {
                            Text(cat.icon).font(.system(size: 18))
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.18)).cornerRadius(11)
                        }
                    }
                }
            }
        }
        .padding(18)
        .foregroundColor(.white)
        .containerBackgroundCompat(brandGradient)
    }
}

@available(iOS 16.0, *)
struct LockView: View {
    let snapshot: Snapshot
    @Environment(\.widgetFamily) var family
    var body: some View {
        if family == .accessoryInline {
            Text("Spendly \(snapshot.monthTotal)")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("SPENDLY").font(.system(size: 10, weight: .semibold)).opacity(0.8)
                Text(snapshot.monthTotal).font(.system(size: 20, weight: .bold))
                Text("This month").font(.system(size: 10)).opacity(0.75)
            }
        }
    }
}

// MARK: - containerBackground shim (iOS 17 requires it; older versions ignore)

extension View {
    @ViewBuilder func containerBackgroundCompat<B: View>(_ background: B) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { background }
        } else {
            ZStack { background; self }
        }
    }
}

// MARK: - Widget definitions

struct SpendlyTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpendlyTodayWidget", provider: Provider()) { entry in
            TodayView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Today's spend")
        .description("Today's total with a mini trend.")
        .supportedFamilies([.systemSmall])
    }
}

struct SpendlyQuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpendlyQuickAddWidget", provider: Provider()) { entry in
            QuickAddView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Quick add")
        .description("Tap a category to log an expense.")
        .supportedFamilies([.systemSmall])
    }
}

struct SpendlyMonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpendlyMonthWidget", provider: Provider()) { entry in
            MonthView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("This month")
        .description("Month total, budget, and quick add.")
        .supportedFamilies([.systemMedium])
    }
}

@available(iOS 16.0, *)
struct SpendlyLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpendlyLockWidget", provider: Provider()) { entry in
            LockView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Spendly total")
        .description("This month's spend at a glance.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

@main
struct SpendlyWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        SpendlyTodayWidget()
        SpendlyQuickAddWidget()
        SpendlyMonthWidget()
        if #available(iOS 16.0, *) {
            SpendlyLockWidget()
        }
    }
}
