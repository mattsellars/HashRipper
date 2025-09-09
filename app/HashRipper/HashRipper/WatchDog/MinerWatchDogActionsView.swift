//
//  MinerWatchDogActionsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

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
                    List {
                        ForEach(actionLogs) { actionLog in
                            WatchDogActionItemView(actionLog: actionLog, miners: allMiners)
                                .opacity(actionLog.isRead ? 0.8 : 1.0)
                        }
                    }
                    .listStyle(.inset)
                    
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

#Preview {
    MinerWatchDogActionsView()
}
