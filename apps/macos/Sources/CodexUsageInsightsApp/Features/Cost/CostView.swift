import SwiftUI

struct CostView: View {
    @Bindable var model: AppModel

    private let metrics = [
        GridItem(.adaptive(minimum: 180), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Apply one transparent pricing profile to the imported token buckets so you can estimate API-equivalent cost without pretending it is an official bill.")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                if let importProgress = model.importProgress {
                    ImportActivityBanner(
                        progress: importProgress,
                        hasPriorData: !model.importedSessions.isEmpty
                    )
                }

                pricingProfilePanel

                if model.importedSessions.isEmpty, model.importProgress == nil {
                    ContentUnavailableView(
                        "No imported usage yet",
                        systemImage: "dollarsign.circle",
                        description: Text("Import logs from Dashboard first, then come back here to estimate cost.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else if let costEstimate = model.costEstimate {
                    estimatedCostPanel(costEstimate)
                    trendPanel
                    billableBreakdownPanel(costEstimate)
                    unsupportedMetricsPanel
                } else {
                    unavailableState
                    unsupportedMetricsPanel
                }
            }
            .padding(24)
        }
        .navigationTitle("Cost")
        .onAppear {
            if model.availablePricingProfiles.isEmpty {
                model.refreshPricingProfiles()
            } else {
                model.refreshCostData()
            }
        }
        .onChange(of: model.selectedTrendGranularity) {
            model.refreshCostData()
        }
    }

    private var pricingProfilePanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Pricing Profile", selection: selectedPricingProfileBinding) {
                    Text("No Profile Selected")
                        .tag(String?.none)

                    ForEach(model.availablePricingProfiles, id: \.name) { profile in
                        Text(profile.name)
                            .tag(Optional(profile.name))
                    }
                }
                .pickerStyle(.menu)

                if let selectedProfile = selectedProfile {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedProfile.description)
                            .foregroundStyle(.secondary)
                        Text(selectedProfile.formulaText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        if let reviewedOn = selectedProfile.reviewedOn {
                            Text("Reviewed on \(reviewedOn)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Choose a named pricing profile to unlock estimated cost. Until then, token analytics stay available and dollars stay intentionally unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Pricing Profile", systemImage: "slider.horizontal.3")
        }
    }

    private func estimatedCostPanel(_ costEstimate: CostEstimate) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Estimated Cost")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(costEstimate.profile.name)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: metrics, spacing: 16) {
                    MetricTileView(title: "Estimated Cost", value: currencyString(costEstimate.estimatedCost))
                    MetricTileView(title: "Uncached Input", value: costEstimate.billableTokens.uncachedInputTokens.formatted())
                    MetricTileView(title: "Cached Input", value: costEstimate.billableTokens.cachedInputTokens.formatted())
                    MetricTileView(title: "Output Tokens", value: costEstimate.billableTokens.outputTokens.formatted())
                }

                Text("Estimate only. This applies the selected API-style pricing profile to imported token buckets and is not an official provider bill.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trendPanel: some View {
        GroupBox {
            HStack {
                Text("Estimated Cost Trend")
                    .font(.title3.weight(.semibold))
                Spacer()
                Picker("Granularity", selection: $model.selectedTrendGranularity) {
                    ForEach(TrendGranularity.allCases) { granularity in
                        Text(granularity.title)
                            .tag(granularity)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }

            CostTrendChartView(
                buckets: model.costTrendBuckets,
                granularity: model.selectedTrendGranularity
            )
        }
    }

    private func billableBreakdownPanel(_ costEstimate: CostEstimate) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Billable Token Breakdown")
                    .font(.title3.weight(.semibold))

                breakdownRow(
                    label: "Input Tokens (reported)",
                    value: costEstimate.usage.inputTokens.formatted(),
                    detail: "Total reported input before cached input is split out."
                )
                Divider()
                breakdownRow(
                    label: "Uncached Input (billable)",
                    value: costEstimate.billableTokens.uncachedInputTokens.formatted(),
                    detail: "Computed as input_tokens - cached_input_tokens."
                )
                Divider()
                breakdownRow(
                    label: "Cached Input (billable)",
                    value: costEstimate.billableTokens.cachedInputTokens.formatted(),
                    detail: "Priced as a subset of reported input, not added on top of full input twice."
                )
                Divider()
                breakdownRow(
                    label: "Output Tokens (billable)",
                    value: costEstimate.billableTokens.outputTokens.formatted(),
                    detail: "reasoning_output_tokens remain visible elsewhere but are treated as part of output billing."
                )
            }
        }
    }

    private var unsupportedMetricsPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Unavailable In MVP")
                    .font(.title3.weight(.semibold))

                breakdownRow(
                    label: "Cache Create",
                    value: "Unavailable",
                    detail: "Current local logs do not expose a trustworthy cache-create counter, so the app does not synthesize one."
                )
                Divider()
                breakdownRow(
                    label: "Billing Block",
                    value: "Unavailable",
                    detail: "This product only shows time-range cost estimates and does not claim provider-native billing block totals."
                )
            }
        }
    }

    private var unavailableState: some View {
        ContentUnavailableView(
            "Estimated cost is unavailable",
            systemImage: "dollarsign.circle",
            description: Text("Select a valid pricing profile to compute an estimate from uncached input, cached input, and output tokens.")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var selectedPricingProfileBinding: Binding<String?> {
        Binding(
            get: { model.selectedPricingProfileName },
            set: { model.selectPricingProfile(named: $0) }
        )
    }

    private var selectedProfile: PricingProfile? {
        guard let selectedPricingProfileName = model.selectedPricingProfileName else {
            return nil
        }
        return model.availablePricingProfiles.first(where: { $0.name == selectedPricingProfileName })
    }

    private func breakdownRow(
        label: String,
        value: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.headline)
                Spacer()
                Text(value)
                    .font(.body.weight(.semibold))
            }

            Text(detail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func currencyString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "$0.00"
    }
}
