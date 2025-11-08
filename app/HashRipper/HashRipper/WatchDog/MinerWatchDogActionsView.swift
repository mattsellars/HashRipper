//
//  MinerWatchDogActionsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import Charts

struct MinerWatchDogActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [SortDescriptor<WatchDogActionLog>(\.timestamp, order: .reverse)]
    ) private var actionLogs: [WatchDogActionLog]
    
    @Query private var allMiners: [Miner]
    
    @State private var markAsReadTask: Task<Void, Never>?
    @State private var unreadActionsWhenOpened: [WatchDogActionLog] = []
    
    static let windowGroupId = "miner-watchdog-actions"

    public init() {
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if actionLogs.isEmpty {
                    ContentUnavailableView(
                        "No WatchDog Actions",
                        systemImage: "shield.checkered",
                        description: Text("The WatchDog hasn't performed any automatic miner restarts yet.")
                    )
                } else {
                    // Chart at top showing restarts over time
                    WatchDogRestartChart(actionLogs: actionLogs, allMiners: allMiners)
                        .frame(height: 180)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            Rectangle()
                                .frame(height: 0.5)
                                .foregroundColor(Color(NSColor.separatorColor)),
                            alignment: .bottom
                        )
                    
                    ScrollViewReader { proxy in
                        List {
                            ForEach(actionLogs) { actionLog in
                                WatchDogActionItemView(actionLog: actionLog, miners: allMiners)
                                    .opacity(actionLog.isRead ? 0.8 : 1.0)
                            }
                        }
                        .listStyle(.inset)
                        .onAppear {
                            // Scroll to top without animation when window opens
                            if let firstActionLog = actionLogs.first {
                                proxy.scrollTo(firstActionLog.id, anchor: .top)
                            }
                        }
                    }
                    
                    HStack {
                        Button("Clear All History") {
                            clearAllActions()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                        
                        Spacer()
                        
                        Text("\(actionLogs.count) total actions")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding()
                }
            }
            .navigationTitle("WatchDog Actions")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        // SwiftData auto-updates, but this provides user feedback
                    }
                    .help("Refresh action history")
                }
            }
        }
        .frame(width: 700, height: 600)
        .onAppear {
            startMarkAsReadTimer()
        }
        .onDisappear {
            markVisibleActionsAsRead()
        }
    }
    
    private func clearAllActions() {
        do {
            try modelContext.delete(model: WatchDogActionLog.self)
            try modelContext.save()
        } catch {
            print("Failed to clear WatchDog actions: \(error)")
        }
    }
    
    private func startMarkAsReadTimer() {
        // Capture unread actions that are currently visible
        unreadActionsWhenOpened = actionLogs.filter { !$0.isRead }
        
        // Cancel any existing timer
        markAsReadTask?.cancel()
        
        // Start a 10-second timer
        markAsReadTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            
            if !Task.isCancelled {
                await markVisibleActionsAsRead()
            }
        }
    }
    
    private func markVisibleActionsAsRead() {
        markAsReadTask?.cancel()
        
        Task { @MainActor in
            // Mark the actions that were unread when window opened
            for action in unreadActionsWhenOpened where !action.isRead {
                action.isRead = true
            }
            
            do {
                try modelContext.save()
                print("Marked \(unreadActionsWhenOpened.count) WatchDog actions as read")
            } catch {
                print("Failed to mark WatchDog actions as read: \(error)")
            }
            
            unreadActionsWhenOpened.removeAll()
        }
    }
}

struct WatchDogActionItemView: View {
    let actionLog: WatchDogActionLog
    let miners: [Miner]
    
    private var miner: Miner? {
        miners.first { $0.macAddress == actionLog.minerMacAddress }
    }
    
    private var formattedTime: String {
        let date = Date(timeIntervalSince1970: Double(actionLog.timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: Double(actionLog.timestamp) / 1000.0)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                // Action icon and status
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(actionColor.opacity(0.2))
                            .frame(width: 32, height: 32)
                        Image(systemName: actionIcon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(actionColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(actionTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(relativeTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Unread indicator
                if !actionLog.isRead {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
                
                // Miner info pill
                if let miner = miner {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(miner.hostName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .clipShape(.capsule)
                }
            }
            
            // Reason and details
            VStack(alignment: .leading, spacing: 6) {
                Text("Reason:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text(actionLog.reason)
                    .font(.callout)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Version information if available
            if actionLog.minerFirmwareVersion != nil || actionLog.axeOSVersion != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Firmware Version:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        if let firmwareVersion = actionLog.minerFirmwareVersion {
                            HStack(spacing: 4) {
                                Image(systemName: "f.circle")
                                    .font(.caption2)
                                    .foregroundColor(.purple)
                                Text("Firmware: \(firmwareVersion)")
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                            }
                        }
                        
                        if let axeOSVersion = actionLog.axeOSVersion {
                            HStack(spacing: 4) {
                                Image(systemName: "v.circle")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("AxeOS: \(axeOSVersion)")
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            
            // Footer with exact timestamp and MAC address
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(formattedTime)
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.caption2)
                    Text(actionLog.minerMacAddress)
                        .font(.caption2)
                        .fontDesign(.monospaced)
                }
.foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(actionColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var actionColor: Color {
        switch actionLog.action {
        case .restartMiner:
            return .orange
        }
    }
    
    private var actionIcon: String {
        switch actionLog.action {
        case .restartMiner:
            return "power.circle.fill"
        }
    }
    
    private var actionTitle: String {
        switch actionLog.action {
        case .restartMiner:
            return "Miner Restarted"
        }
    }
}

// MARK: - Restart Chart View

private let kOneHourSeconds: TimeInterval = 3600
struct WatchDogRestartChart: View {
    let actionLogs: [WatchDogActionLog]
    let allMiners: [Miner]
    
    @State private var selectedDataPoint: ChartDataPoint?
    @State private var scrollPosition: ScrollPosition = ScrollPosition()
    
    struct ChartDataPoint: Identifiable, Equatable {
        let id: String
        let date: Date
        let count: Int
        let hour: String
        let actionLogs: [WatchDogActionLog]

        init(date: Date, count: Int, hour: String, actionLogs: [WatchDogActionLog]) {
            self.id = "\(date.timeIntervalSince1970)"
            self.date = date
            self.count = count
            self.hour = hour
            self.actionLogs = actionLogs
        }

        static func == (lhs: ChartDataPoint, rhs: ChartDataPoint) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    private var chartData: [ChartDataPoint] {
        let calendar = Calendar.current
        let currentHour = calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        // Calculate start time: 48 hours ago
        let startTime = calendar.date(byAdding: .hour, value: -48, to: currentHour) ?? currentHour.addingTimeInterval(-48 * kOneHourSeconds)

        // Group existing actions by hour
        let grouped = Dictionary(grouping: actionLogs) { actionLog in
            let date = Date(timeIntervalSince1970: Double(actionLog.timestamp) / 1000.0)
            return calendar.dateInterval(of: .hour, for: date)?.start ?? date
        }

        // Create data points for all hours in the last 48 hours
        var dataPoints: [ChartDataPoint] = []
        var currentIterHour = startTime

        while currentIterHour <= currentHour {
            let actionsForHour = grouped[currentIterHour] ?? []
            dataPoints.append(ChartDataPoint(
                date: currentIterHour,
                count: actionsForHour.count,
                hour: formatter.string(from: currentIterHour),
                actionLogs: actionsForHour
            ))
            currentIterHour = calendar.date(byAdding: .hour, value: 1, to: currentIterHour) ?? currentIterHour.addingTimeInterval(kOneHourSeconds)
        }

        // Set initial selection to most recent hour with data, or current hour
        if selectedDataPoint == nil {
            DispatchQueue.main.async {
                let barsWithData = dataPoints.filter { $0.count > 0 }
                selectedDataPoint = barsWithData.last ?? dataPoints.last
            }
        }

        return dataPoints
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            
            if chartData.isEmpty {
                emptyChartView
            } else {
                chartAndCardView
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(.orange)
            Text("Restart Activity")
                .font(.headline)
                .fontWeight(.medium)
            Spacer()
            Text("\(actionLogs.count) total restarts")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyChartView: some View {
        Text("No data to display")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var chartAndCardView: some View {
        GeometryReader { geometry in
            HStack(spacing: 16) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        chartView
                            .frame(height: geometry.size.height)
                    }
                    .frame(width: geometry.size.width - 276) // Total width minus card width (260) and spacing (16)
                    .scrollTargetLayout()
                    .scrollPosition($scrollPosition, anchor: .trailing)
                    .onChange(of: selectedDataPoint) {
                        guard let id: String = selectedDataPoint?.id else { return }

                        withAnimation {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                    .onAppear {
                        setupInitialSelection()
                        setupInitialScroll()
                    }
                }

                detailCardView
                    .frame(width: 260)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedDataPoint)
    }

    private let selectedGradient = Gradient(colors: [Color.orange, Color.blue])
    private let unselectedGradient = Gradient(colors: [Color.orange, Color.orange.opacity(0.6)])

    private func gradient(isSelected: Bool) -> Gradient {
        return isSelected ? selectedGradient : unselectedGradient
    }
    private var chartView: some View {
        Chart(chartData, id: \.id) { point in
            let isSelected = selectedDataPoint?.date == point.date
            let barOpacity = point.count > 0 ? 1.0 : 0.3
            BarMark(
                x: .value("Time", point.date),
                y: .value("Restarts", point.count)
            )
            .foregroundStyle(gradient(isSelected: isSelected))
            .opacity(barOpacity)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 1)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(DateFormatter.shortTime.string(from: date))
                            .font(.system(size: 10))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let count = value.as(Int.self) {
                        Text("\(count)")
                            .font(.system(size: 10))
                    }
                }
            }
        }
        .chartYScale(domain: 0...(chartData.map(\.count).max() ?? 0) + 1)
        .chartGesture { chartProxy in
            SpatialTapGesture()
                .onEnded { value in
                    handleChartTap(location: value.location, chartProxy: chartProxy)
                }
        }
        .frame(width: CGFloat(chartData.count * 50))
    }
    
    private var detailCardView: some View {
        RestartDetailCard(
            dataPoint: selectedDataPoint,
            allMiners: allMiners,
            onDismiss: {
                selectedDataPoint = nil
            }
        )
    }
    
    private func setupInitialSelection() {
        if selectedDataPoint == nil {
            let barsWithData = chartData.filter { $0.count > 0 }
            if let mostRecent = barsWithData.first {
                selectedDataPoint = mostRecent
            }
        }
    }
    
    private func setupInitialScroll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let latestBar = chartData.first {
                scrollPosition.scrollTo(id: latestBar.id, anchor: .bottom)
            }
        }
    }
    
    private func handleChartTap(location: CGPoint, chartProxy: ChartProxy) {
        // Convert tap location to chart coordinates
        if let tappedDate: Date = chartProxy.value(atX: location.x) {
            // Find the closest data point to the tapped location
            let closestDataPoint = chartData.min { point1, point2 in
                abs(point1.date.timeIntervalSince(tappedDate)) < abs(point2.date.timeIntervalSince(tappedDate))
            }
            
            if let dataPoint = closestDataPoint {
                selectedDataPoint = dataPoint
            }
        }
    }
    
}

struct RestartDetailCard: View {
    let dataPoint: WatchDogRestartChart.ChartDataPoint?
    let allMiners: [Miner]
    let onDismiss: () -> Void
    
    private var minersForActions: [(miner: Miner?, action: WatchDogActionLog)] {
        guard let dataPoint = dataPoint else { return [] }
        return dataPoint.actionLogs.map { action in
            let miner = allMiners.first { $0.macAddress == action.minerMacAddress }
            return (miner: miner, action: action)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let dataPoint = dataPoint {
                        Text("Restarts at \(dataPoint.hour)")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("\(dataPoint.count) miners restarted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Recent Restarts")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("No recent activity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            Divider()
            
            // Miner list or empty state
            if minersForActions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No restart activity")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("WatchDog hasn't restarted any miners recently")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(minersForActions, id: \.action.id) { minerAction in
                            HStack(spacing: 6) {
                                Image(systemName: "cpu")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .frame(width: 14)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    if let miner = minerAction.miner {
                                        Text(miner.hostName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        Text(miner.ipAddress)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Unknown Miner")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.secondary)
                                        Text(minerAction.action.minerMacAddress.suffix(8))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Exact time
                                Text(formatExactTime(minerAction.action.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fontDesign(.monospaced)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private func formatExactTime(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h"
        return formatter
    }()
}

#Preview {
    MinerWatchDogActionsView()
}
