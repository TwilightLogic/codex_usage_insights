import Charts
import SwiftUI

struct UsageTrendChartView: View {
    let buckets: [UsageTrendBucket]
    let granularity: TrendGranularity

    var body: some View {
        if buckets.isEmpty {
            ContentUnavailableView(
                "No trend data yet",
                systemImage: "chart.xyaxis.line",
                description: Text("Import logs to see token usage over time.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Period", label(for: bucket.startDate)),
                    y: .value("Total Tokens", bucket.usage.totalTokens)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(6)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
        }
    }

    private func label(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent

        switch granularity {
        case .day:
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        case .week:
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        case .month:
            formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
        }

        return formatter.string(from: date)
    }
}
