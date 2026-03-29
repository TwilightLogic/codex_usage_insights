import SwiftUI

struct ImportActivityBanner: View {
    let progress: ImportProgress
    let hasPriorData: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(hasPriorData ? "Refreshing Imported Data" : "Importing Local Logs")
                    .font(.headline)
                ProgressView(value: progress.fractionCompleted)
                HStack(spacing: 16) {
                    Text("Processed \(progress.processedFiles) of \(progress.totalFiles)")
                    Text("Sessions \(progress.countedSessions)")
                    Text("Warnings \(progress.warningCount)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Refresh Status", systemImage: "arrow.triangle.2.circlepath")
        }
    }
}
