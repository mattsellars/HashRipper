//
//  MinerChartsViewModel.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class MinerChartsViewModel: ObservableObject {
    @Published var miners: [Miner] = []
    @Published var chartData: [ChartSegmentedDataEntry] = []
    @Published var chartDataBySegment: [ChartSegments: [ChartSegmentedDataEntry]] = [:]
    @Published var isLoading = false
    @Published var currentMiner: Miner?
    @Published var currentPage = 0
    @Published var totalDataPoints = 0
    @Published var hasMoreData = false
    @Published var isPaginating = false

    private var modelContext: ModelContext?
    private let initialMinerMacAddress: String?
    private var notificationSubscription: AnyCancellable?
    private var debounceTask: Task<Void, Never>?

    // Pagination settings
    let dataPointsPerPage = 200 // Show 200 data points per page
    
    init(modelContext: ModelContext?, initialMinerMacAddress: String?) {
        self.modelContext = modelContext
        self.initialMinerMacAddress = initialMinerMacAddress
    }
    
    deinit {
        notificationSubscription?.cancel()
        debounceTask?.cancel()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    private func setupNotificationSubscription() {
        notificationSubscription = NotificationCenter.default
            .publisher(for: .minerUpdateInserted)
            .compactMap { notification in
                notification.userInfo?["macAddress"] as? String
            }
            .debounce(for: .seconds(0.2), scheduler: RunLoop.main)
            .filter { [weak self] macAddress in
                self?.currentMiner?.macAddress == macAddress
            }
            .sink { [weak self] _ in
                self?.refreshChartDataWithDebounce()
            }
    }
    
    private func refreshChartDataWithDebounce() {
        // Cancel any existing debounce task
        debounceTask?.cancel()
        
        debounceTask = Task { @MainActor in
            // Wait 200ms to batch multiple rapid updates
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            if !Task.isCancelled, let miner = currentMiner {
                await loadChartData(for: miner, showLoading: false)
            }
        }
    }
    
    func loadMiners() async {
        guard let modelContext = modelContext else { return }
        
        isLoading = true
        
        do {
            let descriptor = FetchDescriptor<Miner>(
                sortBy: [SortDescriptor(\Miner.hostName)]
            )
            miners = try modelContext.fetch(descriptor)
            
            // Find the initial miner by macAddress if provided
            if let initialMacAddress = initialMinerMacAddress,
               let initialMiner = miners.first(where: { $0.macAddress == initialMacAddress }) {
                currentMiner = initialMiner
                await loadChartData(for: initialMiner)
            } else if let firstMiner = miners.first {
                // Fallback to first miner if no initial miner or initial not found
                currentMiner = firstMiner
                await loadChartData(for: firstMiner)
            }
            
            // Set up notification subscription after initial load
            setupNotificationSubscription()
        } catch {
            print("Error loading miners: \(error)")
        }
        
        isLoading = false
    }
    
    func loadChartData(for miner: Miner, showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        } else {
            isPaginating = true
        }

        // Capture pagination values on main actor
        let currentPageValue = currentPage
        let dataPointsPerPageValue = dataPointsPerPage
        let macAddress = miner.macAddress

        // Perform database operations on background thread
        let result = await Task.detached {
            // Use a background context from the shared database for better performance
            let backgroundContext = ModelContext(SharedDatabase.shared.modelContainer)

            do {
                // First, get total count for pagination info
                let countDescriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == macAddress
                    }
                )
                let allUpdates = try backgroundContext.fetch(countDescriptor)
                let totalCount = allUpdates.count

                // Calculate pagination
                let offset = currentPageValue * dataPointsPerPageValue
                let hasMore = offset + dataPointsPerPageValue < totalCount

                // Fetch paginated data - most recent first, then take our window
                var descriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == macAddress
                    },
                    sortBy: [SortDescriptor(\MinerUpdate.timestamp, order: .reverse)]
                )
                descriptor.fetchLimit = offset + dataPointsPerPageValue

                let updates = try backgroundContext.fetch(descriptor)

                // Take the window we want (skip older data, take our page)
                let pageUpdates = Array(updates.dropFirst(offset).prefix(dataPointsPerPageValue))

                // Reverse to get chronological order (oldest first) for proper chart display
                let sortedUpdates = pageUpdates.reversed()

                let nextChartData = sortedUpdates.map { update in
                    ChartSegmentedDataEntry(
                        time: Date(milliseconds: update.timestamp),
                        values: [
                            ChartSegmentValues(primary: update.hashRate, secondary: nil),
                            ChartSegmentValues(primary: update.temp ?? 0, secondary: nil),
                            ChartSegmentValues(primary: update.vrTemp ?? 0, secondary: nil),
                            ChartSegmentValues(primary: Double(update.fanrpm ?? 0), secondary: Double(update.fanspeed ?? 0)),
                            ChartSegmentValues(primary: update.power, secondary: nil),
                            ChartSegmentValues(primary: (update.voltage ?? 0) / 1000.0, secondary: nil)
                        ]
                    )
                }

                return (nextChartData, totalCount, hasMore, nil as Error?)
            } catch {
                return ([], 0, false, error)
            }
        }.value

        // Update UI on main actor with smooth animation
        let (nextChartData, totalCount, hasMore, error) = result

        if let error = error {
            print("Error loading chart data: \(error)")
            chartData = []
            totalDataPoints = 0
            hasMoreData = false
        } else {
            totalDataPoints = totalCount
            hasMoreData = hasMore

            // Update all charts simultaneously with optimized animation
            let chartsToShow: [ChartSegments] = ChartSegments.allCases.filter({ $0 != ChartSegments.voltageRegulatorTemperature })

            withAnimation(.easeInOut(duration: 0.3)) {
                chartData = nextChartData

                // Update all segment-specific data at once
                for segment in chartsToShow {
                    chartDataBySegment[segment] = nextChartData
                }

                // For asicTemperature chart, also update VR temperature data
                chartDataBySegment[.voltageRegulatorTemperature] = nextChartData
            }
        }

        if showLoading {
            isLoading = false
        } else {
            isPaginating = false
        }
    }


    func selectMiner(_ miner: Miner) async {
        guard currentMiner?.id != miner.id else { return }

        currentMiner = miner
        currentPage = 0 // Reset to most recent data when switching miners
        await loadChartData(for: miner)

        // Update notification subscription for the new miner
        setupNotificationSubscription()
    }
    
    func nextMiner() async {
        guard let current = currentMiner,
              let currentIndex = miners.firstIndex(where: { $0.id == current.id }),
              currentIndex < miners.count - 1 else { return }

        await selectMiner(miners[currentIndex + 1])
    }

    func previousMiner() async {
        guard let current = currentMiner,
              let currentIndex = miners.firstIndex(where: { $0.id == current.id }),
              currentIndex > 0 else { return }

        await selectMiner(miners[currentIndex - 1])
    }

    // Pagination methods
    func goToNewerData() async {
        guard currentPage > 0, let miner = currentMiner else { return }
        currentPage -= 1
        await loadChartData(for: miner, showLoading: false)
    }

    func goToOlderData() async {
        guard hasMoreData, let miner = currentMiner else { return }
        currentPage += 1
        await loadChartData(for: miner, showLoading: false)
    }

    func goToMostRecentData() async {
        guard currentPage > 0, let miner = currentMiner else { return }
        currentPage = 0
        await loadChartData(for: miner, showLoading: false)
    }

    var canGoToNewerData: Bool {
        currentPage > 0
    }

    var canGoToOlderData: Bool {
        hasMoreData
    }

    var currentPageInfo: String {
        if totalDataPoints == 0 {
            return "No data"
        }

        let startIndex = currentPage * dataPointsPerPage + 1
        let endIndex = min((currentPage + 1) * dataPointsPerPage, totalDataPoints)

        if currentPage == 0 {
            return "Most recent \(endIndex) of \(totalDataPoints) data points"
        } else {
            return "Showing \(startIndex)-\(endIndex) of \(totalDataPoints) data points"
        }
    }
    
    var isNextMinerButtonDisabled: Bool {
        guard let current = currentMiner,
              let currentIndex = miners.firstIndex(where: { $0.id == current.id }) else {
            return true
        }
        return currentIndex == miners.count - 1
    }
    
    var isPreviousMinerButtonDisabled: Bool {
        guard let current = currentMiner,
              let currentIndex = miners.firstIndex(where: { $0.id == current.id }) else {
            return true
        }
        return currentIndex == 0
    }
    
    func mostRecentUpdateTitleValue(segmentIndex: Int) -> String {
        // Use the segment-specific data if available, otherwise fall back to general chartData
        let segment = ChartSegments(rawValue: segmentIndex) ?? .hashRate
        let value = chartDataBySegment[segment]?.last?.values[segmentIndex] ?? chartData.last?.values[segmentIndex]
        switch ChartSegments(rawValue: segmentIndex) ?? .hashRate {
        case .hashRate:
            let f = formatMinerHashRate(rawRateValue: value?.primary ?? 0)
            return "\(f.rateString)\(f.rateSuffix)"
        case .voltage, .power:
            return String(format: "%.1f", value?.primary ?? 0)
        case .voltageRegulatorTemperature, .asicTemperature:
            let mf = MeasurementFormatter()
            mf.unitOptions = .providedUnit
            mf.numberFormatter.maximumFractionDigits = 1
            let temp = Measurement(value: value?.primary ?? 0, unit: UnitTemperature.celsius)
            return mf.string(from: temp)
        case .fanRPM:
            let fanRPM = Int(value?.primary ?? 0)
            let fanSpeedPct = Int(value?.secondary ?? 0)
            return "\(fanRPM) · \(fanSpeedPct)%"
        }
    }
}
