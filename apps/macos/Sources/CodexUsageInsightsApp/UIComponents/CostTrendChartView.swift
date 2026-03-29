import Charts
import SwiftUI

struct CostTrendChartView: View {
    let buckets: [CostTrendBucket]
    let granularity: TrendGranularity

    var body: some View {
        if buckets.isEmpty {
            ContentUnavailableView(
                "No cost trend yet",
                systemImage: "chart.line.text.clipboard",
                description: Text("Select a pricing profile to see estimated cost over time.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Period", label(for: bucket.startDate)),
                    y: .value("Estimated Cost", NSDecimalNumber(decimal: bucket.estimatedCost).doubleValue)
                )
                .foregroundStyle(Color.green.gradient)
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
