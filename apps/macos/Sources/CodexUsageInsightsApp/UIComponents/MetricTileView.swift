import SwiftUI

struct MetricTileView: View {
    let title: String
    let value: String
    var emphasis: Bool = true

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(emphasis ? .title3.weight(.semibold) : .body.weight(.medium))
                    .foregroundStyle(emphasis ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
