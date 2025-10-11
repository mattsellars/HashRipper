//
//  StatusBarPopoverView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

struct StatusBarPopoverView: View {
    @ObservedObject var manager: StatusBarManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Query private var allMiners: [Miner]

    @State private var topMiners: [TopMinerData] = []

    struct TopMinerData: Identifiable {
        var id: String {
            miner.macAddress
        }
        let miner: Miner
        let bestDiff: String
        let bestDiffValue: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("HashRipper Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            Divider()

            // Stats grid
            VStack(spacing: 8) {
                StatusStatRow(
                    icon: "bolt.fill",
                    label: "Hash Rate",
                    value: formatHashRate(manager.totalHashRate),
                    color: .green
                )

                StatusStatRow(
                    icon: "power",
                    label: "Power",
                    value: formatPower(manager.totalPower),
                    color: .orange
                )

                StatusStatRow(
                    icon: "server.rack",
                    label: "Miners",
                    value: "\(manager.activeMiners) active / \(manager.minerCount) total",
                    color: .blue
                )
            }

            Divider()

            // Top miners section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "medal")
                        .font(.title3)
                        .foregroundColor(.orange)
                    Text("Top Miners")
                        .font(.headline)
                        .fontWeight(.medium)
                    Spacer()
                }

                ForEach(0..<min(3, topMiners.count), id: \.self) { index in
                    let minerData = topMiners[index]

                    HStack(spacing: 6) {
                        // Rank badge (smaller for popover)
                        ZStack {
                            Circle()
                                .fill(rankColor(for: index))
                                .frame(width: 18, height: 18)
                            Text("\(index + 1)")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                        }

                        // Miner info (compact)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(minerData.miner.hostName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            HStack(spacing: 2) {
                                Image(systemName: "medal.star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(minerData.bestDiff)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(.orange)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if topMiners.isEmpty {
                    Text("No active miners")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            }

            Divider()

            // Quick actions
            HStack {
                Button("Open HashRipper") {
                    openMainWindow()
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Refresh") {
                    // Trigger an immediate refresh of stats
                    NotificationCenter.default.post(name: .refreshMinerStats, object: nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            loadTopMiners()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { notification in
            if let macAddress = notification.userInfo?["macAddress"] as? String {
                checkAndUpdateIfNeeded(for: macAddress)
            }
        }
    }

    private func openMainWindow() {
        print("🪟 StatusBarPopoverView.openMainWindow() called")

        // Close the popover first
        if let popover = manager.popover {
            popover.performClose(nil)
        }

        // Activate the app
        NSApp.activate(ignoringOtherApps: true)

        // First try to find existing visible main window
        var foundExistingWindow = false
        print("🪟 Checking \(NSApp.windows.count) total windows")

        for window in NSApp.windows {
            let className = NSStringFromClass(type(of: window))
            print("🪟 Window: \(className), title: '\(window.title)', visible: \(window.isVisible), canBecomeKey: \(window.canBecomeKey), miniaturized: \(window.isMiniaturized)")

            // Skip system windows and popover windows
            if className.contains("StatusBar") ||
               className.contains("MenuBar") ||
               className.contains("Popover") ||
               window.title.contains("Settings") ||
               window.title.contains("Downloads") ||
               window.title.contains("WatchDog") ||
               window.title.contains("Firmware") {
                print("🪟 Skipping system window: \(className)")
                continue
            }

            // Look for visible main app window - must have HashRipper title specifically
            if window.canBecomeKey &&
               window.isVisible &&
               !window.isMiniaturized &&
               window.title == "HashRipper" {
                print("🪟 Found existing visible main window: \(className), title: '\(window.title)'")
                print("🪟 Window frame: \(window.frame)")
                print("🪟 Window level: \(window.level)")
                window.makeKeyAndOrderFront(nil)
                foundExistingWindow = true
                break
            }
        }

        if !foundExistingWindow {
            print("🪟 No existing main window found, opening via manager")
            // Use the StatusBarManager which has logic to trigger Window menu
            manager.openMainWindow()

            // Restore window size if we have one saved
            if let savedFrame = manager.savedWindowFrame {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.restoreWindowFrame(savedFrame)
                }
            }
        }
    }

    private func restoreWindowFrame(_ frame: NSRect) {
        // Find the newly created main window and restore its frame
        for window in NSApp.windows {
            let className = NSStringFromClass(type(of: window))

            if !className.contains("StatusBar") &&
               !className.contains("MenuBar") &&
               !window.title.contains("Settings") &&
               !window.title.contains("Downloads") &&
               !window.title.contains("WatchDog") &&
               !window.title.contains("Firmware") &&
               window.canBecomeKey &&
               window.isVisible {

                print("🪟 Restoring window frame to: \(frame)")
                window.setFrame(frame, display: true)
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }

    private func formatHashRate(_ hashRate: Double) -> String {
        let formatted = formatMinerHashRate(rawRateValue: hashRate)
        return "\(formatted.rateString) \(formatted.rateSuffix)"
    }

    private func formatPower(_ power: Double) -> String {
        if power >= 1000 {
            return String(format: "%.2f kW", power / 1000)
        } else if power > 0 {
            return String(format: "%.0f W", power)
        } else {
            return "0 W"
        }
    }

    private func rankColor(for index: Int) -> Color {
        switch index {
        case 0: return .yellow  // Gold
        case 1: return .gray    // Silver
        case 2: return .brown   // Bronze
        default: return .blue
        }
    }

    private func checkAndUpdateIfNeeded(for macAddress: String) {
        Task { @MainActor in
            // Find the miner that was updated
            guard let updatedMiner = allMiners.first(where: { $0.macAddress == macAddress }) else { return }

            // Get the latest update for this miner
            guard let latestUpdate = updatedMiner.getLatestUpdate(from: modelContext),
                  let bestDiff = latestUpdate.bestDiff,
                  !bestDiff.isEmpty && bestDiff != "N/A" else { return }

            let bestDiffValue = DifficultyParser.parseDifficultyValue(bestDiff)
            guard bestDiffValue > 0 else { return }

            // Check if this miner is already in the top 3
            let isAlreadyInTop3 = topMiners.contains { $0.miner.macAddress == macAddress }

            if isAlreadyInTop3 {
                // If already in top 3, always reload to update the value
                loadTopMiners()
                return
            }

            // If we have less than 3 miners, always add new ones
            if topMiners.count < 3 {
                loadTopMiners()
                return
            }

            // Check if this new value would beat the 3rd place (lowest of top 3)
            let lowestTop3Value = topMiners.last?.bestDiffValue ?? 0
            if bestDiffValue > lowestTop3Value {
                loadTopMiners()
            }
        }
    }

    private func loadTopMiners() {
        Task { @MainActor in

            var minerDataArray: [TopMinerData] = []

            for miner in allMiners {
                // Get the latest update for this miner using the existing extension
                if let latestUpdate = miner.getLatestUpdate(from: modelContext) {
                    if let bestDiff = latestUpdate.bestDiff,
                       !bestDiff.isEmpty && bestDiff != "N/A" {

                        let bestDiffValue = DifficultyParser.parseDifficultyValue(bestDiff)
                        if bestDiffValue > 0 {
                            minerDataArray.append(TopMinerData(
                                miner: miner,
                                bestDiff: bestDiff,
                                bestDiffValue: bestDiffValue
                            ))

                        }
                    }
                }
            }

            // Sort by bestDiffValue in descending order and take top 3
            let top3 = Array(minerDataArray.sorted { $0.bestDiffValue > $1.bestDiffValue }.prefix(3))

            withAnimation {
                topMiners = top3
            }
        }
    }

}

struct StatusStatRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)

            Text(label)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

// Notification name for refresh action
extension Notification.Name {
    static let refreshMinerStats = Notification.Name("refreshMinerStats")
}
