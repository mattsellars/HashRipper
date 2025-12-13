//
//  MinerWebsocketRecordingScreen.swift
//  HashRipper
//
//  Created by Matt Sellars on 7/30/25.
//
import AppKit
import AxeOSClient
import Combine
import OSLog
import SwiftData
import SwiftUI

struct MinerWebsocketRecordingScreen: View {
    static let windowGroupId = "HashRipper.MinerWebsocketRecordingScreen"
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.minerClientManager) private var minerClientManager
    @Query(sort: \Miner.hostName) private var allMiners: [Miner]

    @State private var selectedMiner: Miner? = nil

    var isRecording = false // replace with state check

    var body: some View {
        VStack {
            HStack {
                Picker("Select Miner", selection: $selectedMiner) {
                    Text("Choose…").tag("Optional<Miner>.none")
                    ForEach(allMiners) { miner in
                        MinerPickerSelectionView(
                            minerHostName: miner.hostName,
                            minerIpAddress: miner.ipAddress
                        ).tag(miner)
                    }
                }
                .pickerStyle(.automatic)
            }
//            .overlay(alignment: .topTrailing) {
//                GeometryReader { geometry in
//                    Button(action: {
//                        dismissWindow(id: Self.windowGroupId)
//                    }) {
//                        Image(systemName: "xmark")
//                    }.position(x: geometry.size.width - 24, y: 18)
//                }
//            }
            Spacer()
            if let selectedMiner = selectedMiner {
                WebsocketFileOrStartRecordingView(
                    minerHostName: selectedMiner.hostName,
                    minerIpAddress: selectedMiner.ipAddress
                ).id(selectedMiner.ipAddress)
            }
        }
        .padding(12)
    }
}

struct WebsocketFileOrStartRecordingView: View {
    @StateObject private var viewModel: MinerSelectionViewModel

    init(minerHostName: String, minerIpAddress: String) {
        self._viewModel = StateObject(wrappedValue: .init(
            minerHostName: minerHostName,
            minerIpAddress: minerIpAddress,
            registry: MinerWebsocketRecordingSessionRegistry.shared
        ))
    }

    var body: some View {
        VStack {
            switch (viewModel.recordingState) {
            case .idle:
                HStack {
                    Button(
                        action: {
                            viewModel.clearMessages()
                            Task { await viewModel.session.startRecording() }
                        },
                        label: { Text("View websocket logs") }
                    )
                }
                VStack {
                    Spacer()
                }.background(Color.black)
                    .padding(12)
            case .recording(let file):
                VStack(spacing: 8) {
                    HStack {
                        Text("Viewing websocket logs")
                            .font(.headline)
                        Spacer()

                        // File recording toggle
                        Button(
                            action: {
                                Task { await viewModel.session.toggleFileWriting() }
                            },
                            label: {
                                if viewModel.session.isWritingToFile {
                                    Label("Stop File Recording", systemImage: "stop.circle.fill")
                                        .foregroundStyle(.red)
                                } else {
                                    Label("Record to File", systemImage: "record.circle")
                                        .foregroundStyle(.orange)
                                }
                            }
                        )

                        // Show in Finder button (only visible when writing to file)
                        if let fileURL = viewModel.session.currentFileURL {
                            Button(
                                action: {
                                    showInFinder(fileURL: fileURL)
                                },
                                label: {
                                    Label("Show in Finder", systemImage: "folder")
                                }
                            )
                        }

                        Button(
                            action: {
                                Task { await viewModel.session.stopRecording() }
                            },
                            label: {
                                Label("Stop", systemImage: "stop.fill")
                                    .foregroundStyle(.red)
                            }
                        )
                    }
                    .padding(.horizontal, 12)

                    // File status display
                    if let fileURL = viewModel.session.currentFileURL {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.green)
                            Text("Writing to: \(fileURL.lastPathComponent)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    }

                    WebsocketMessagesView(viewModel: viewModel)
                        .padding(12)
                }
            }
        }
        .onAppear {
            // Sync state in case session state changed while view was not visible
            viewModel.syncStateFromSession()
        }
    }

    func showInFinder(fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}


@MainActor
class MinerSelectionViewModel: ObservableObject, Identifiable {
    var id: String { minerIpAddress }

    @Published var isRecording: Bool = false
    var cancellables: Set<AnyCancellable> = []
    @Published var recordingState: MinerWebsocketDataRecordingSession.RecordingState
    @Published var logEntries: [WebSocketLogEntry] = []

    // Filtering
    @Published var selectedLevels: Set<WebSocketLogEntry.LogLevel> = []
    @Published var selectedComponent: WebSocketLogEntry.LogComponent? = nil
    @Published var searchText: String = ""

    let minerHostName: String
    let minerIpAddress: String

    let session: MinerWebsocketDataRecordingSession
    init(minerHostName: String, minerIpAddress: String, session: MinerWebsocketDataRecordingSession) {
        self.minerHostName = minerHostName
        self.minerIpAddress = minerIpAddress
        self.session = session
        self.recordingState = session.state
        self.isRecording = session.state != .idle

        Logger.viewModelLogger.debug("MinerSelectionViewModel init for \(minerIpAddress), session.state: \(String(describing: session.state))")

        // Subscribe to recording state changes
        session.recordingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self = self else { return }
                Logger.viewModelLogger.debug("recordingPublisher received state: \(String(describing: newState)) for \(self.minerIpAddress)")
                self.recordingState = newState
                self.isRecording = newState != .idle
            }
            .store(in: &cancellables)

        // Subscribe to structured log entries
        session.logStore.entriesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                self?.logEntries = entries
            }
            .store(in: &cancellables)

        // Load existing entries from logStore on init
        Task {
            let existingEntries = await session.logStore.getEntries()
            await MainActor.run {
                self.logEntries = existingEntries
            }
        }
    }

    deinit {
        Logger.viewModelLogger.debug("MinerSelectionViewModel deinit for \(self.minerIpAddress)")
    }

    func clearMessages() {
        Task {
            await session.logStore.clear()
        }
    }

    var filteredLogEntries: [WebSocketLogEntry] {
        var filtered = logEntries

        // Filter by level - if selectedLevels is empty, show all; otherwise only show selected
        if !selectedLevels.isEmpty {
            filtered = filtered.filter { selectedLevels.contains($0.level) }
        }

        if let component = selectedComponent {
            filtered = filtered.filter { $0.component == component }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.rawText.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    func isLevelEnabled(_ level: WebSocketLogEntry.LogLevel) -> Bool {
        // If no levels are selected, all are enabled (showing all logs)
        if selectedLevels.isEmpty {
            return true
        }
        // Otherwise, only selected levels are enabled
        return selectedLevels.contains(level)
    }

    func toggleLevel(_ level: WebSocketLogEntry.LogLevel) {
        if selectedLevels.isEmpty {
            // If all are currently shown, clicking one means "show only this one"
            // Actually, let's disable just this one and enable all others
            selectedLevels = Set(WebSocketLogEntry.LogLevel.allCases.filter { $0 != level })
        } else if selectedLevels.contains(level) {
            // Remove this level from the filter
            selectedLevels.remove(level)
        } else {
            // Add this level to the filter
            selectedLevels.insert(level)
        }
    }

    /// Syncs the view model state with the session's actual state
    func syncStateFromSession() {
        let currentSessionState = session.state
        Logger.viewModelLogger.debug("syncStateFromSession for \(self.minerIpAddress): session.state=\(String(describing: currentSessionState)), recordingState=\(String(describing: self.recordingState))")
        if recordingState != currentSessionState {
            Logger.viewModelLogger.debug("State mismatch detected, updating to \(String(describing: currentSessionState))")
            recordingState = currentSessionState
            isRecording = currentSessionState != .idle
        }
    }

    convenience init(minerHostName: String, minerIpAddress: String, registry: MinerWebsocketRecordingSessionRegistry) {
        self.init(
            minerHostName: minerHostName,
            minerIpAddress: minerIpAddress,
            session: registry.getOrCreateRecordingSession(
                minerHostName: minerHostName,
                minerIpAddress: minerIpAddress
            )
        )
    }
}

fileprivate extension Logger {
    static let viewModelLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HashRipper", category: "MinerSelectionViewModel")
}

struct MinerPickerSelectionView: View {
    @StateObject private var viewModel: MinerSelectionViewModel
    init(minerHostName: String, minerIpAddress: String) {
        self._viewModel = StateObject(wrappedValue: .init(minerHostName: minerHostName, minerIpAddress: minerIpAddress, registry: MinerWebsocketRecordingSessionRegistry.shared))
    }
    var body: some View {
        HStack {
            Text(viewModel.minerHostName).tag(viewModel.minerIpAddress)
            // if recording use "record.circle.fill"
            Image(systemName: viewModel.isRecording ? "record.circle.fill" : "record.circle")
                .foregroundStyle(viewModel.isRecording ? .red : .gray)
        }
    }
}

//class FileWatcher: ObservableObject {
//    @Published var lines: [String] = []
//
//    private var fileDescriptor: CInt = -1
//    private var source: DispatchSourceFileSystemObject?
//    private let fileURL: URL
//    private var lastFileSize: UInt64 = 0
//    private var lineIdCounter: Int = 0
//
//    init(fileURL: URL) {
//        self.fileURL = fileURL
//        startMonitoring()
//        readFile() // Initial read
//    }
//
//    deinit {
//        stopMonitoring()
//    }
//
//    private func startMonitoring() {
//        guard fileDescriptor == -1 else { return }
//
//        fileDescriptor = open(fileURL.path, O_EVTONLY)
//        guard fileDescriptor != -1 else { return }
//
//        source = DispatchSource.makeFileSystemObjectSource(
//            fileDescriptor: fileDescriptor,
//            eventMask: .write,
//            queue: .main
//        )
//
//        source?.setEventHandler { [weak self] in
//            self?.readNewData()
//        }
//
//        source?.setCancelHandler { [weak self] in
//            if let fd = self?.fileDescriptor, fd != -1 {
//                close(fd)
//                self?.fileDescriptor = -1
//            }
//        }
//
//        source?.resume()
//    }
//
//    private func stopMonitoring() {
//        source?.cancel()
//        source = nil
//    }
//
//    private func readFile() {
//        guard let data = try? Data(contentsOf: fileURL),
//              let contents = String(data: data, encoding: .utf8) else {
//            return
//        }
//
//        let newLines = contents.components(separatedBy: .newlines).filter { !$0.isEmpty }
//        lastFileSize = UInt64(data.count)
//
//        DispatchQueue.main.async {
//            self.lines = newLines
//            self.lineIdCounter = newLines.count
//        }
//    }
//
//    private func readNewData() {
//        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return }
//        defer { fileHandle.closeFile() }
//
//        let currentFileSize = fileHandle.seekToEndOfFile()
//        guard currentFileSize > lastFileSize else { return }
//
//        fileHandle.seek(toFileOffset: lastFileSize)
//        let newData = fileHandle.readDataToEndOfFile()
//        guard let newContent = String(data: newData, encoding: .utf8) else { return }
//
//        let newLines = newContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
//        lastFileSize = currentFileSize
//
//        DispatchQueue.main.async {
//            self.lines.append(contentsOf: newLines)
//        }
//    }
//}

struct WebsocketMessagesView: View {

    @ObservedObject
    var viewModel: MinerSelectionViewModel

    private func colorForLevel(_ level: WebSocketLogEntry.LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .yellow
        case .info: return .green
        case .debug: return .cyan
        case .verbose: return .white
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter controls
            HStack(spacing: 12) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search logs...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
                .frame(maxWidth: 300)

                // Level filter toggle buttons
                HStack(spacing: 4) {
                    ForEach(WebSocketLogEntry.LogLevel.allCases, id: \.self) { level in
                        LevelToggleButton(
                            level: level,
                            isEnabled: viewModel.isLevelEnabled(level),
                            action: {
                                viewModel.toggleLevel(level)
                            }
                        )
                    }
                }

                // Clear filters button
                if !viewModel.selectedLevels.isEmpty || !viewModel.searchText.isEmpty {
                    Button("Clear Filters") {
                        viewModel.selectedLevels.removeAll()
                        viewModel.searchText = ""
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                // Entry count
                Text("\(viewModel.filteredLogEntries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.black.opacity(0.3))

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.filteredLogEntries.enumerated()), id: \.1.id) { index, entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onChange(of: viewModel.filteredLogEntries.count) { _ in
                    if let lastEntry = viewModel.filteredLogEntries.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

/// A toggle button for filtering log levels
struct LevelToggleButton: View {
    let level: WebSocketLogEntry.LogLevel
    let isEnabled: Bool
    let action: () -> Void

    private var backgroundColor: Color {
        switch level {
        case .error: return .red
        case .warning: return .yellow
        case .info: return .green
        case .debug: return .cyan
        case .verbose: return .white
        }
    }

    private var tooltip: String {
        let status = isEnabled ? "Hide" : "Show"
        return "\(status) \(level.displayName) logs"
    }

    var body: some View {
        Button(action: action) {
            Text(level.rawValue)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(backgroundColor.opacity(isEnabled ? 1.0 : 0.3))
                .foregroundColor(isEnabled ? .black : .gray)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

/// A view that displays a single log entry with color coding
struct LogEntryRow: View {
    let entry: WebSocketLogEntry

    var body: some View {
        Text(cleanedMessage)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(colorForLevel(entry.level))
            .padding(.horizontal, 4)
            .textSelection(.enabled)
    }

    private var cleanedMessage: String {
        // Remove all ANSI escape codes from the raw text
        let pattern = #"\[[0-9;]+m"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return entry.rawText
        }
        let range = NSRange(entry.rawText.startIndex..., in: entry.rawText)
        return regex.stringByReplacingMatches(in: entry.rawText, range: range, withTemplate: "")
    }

    private func colorForLevel(_ level: WebSocketLogEntry.LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .yellow
        case .info: return .green
        case .debug: return .cyan
        case .verbose: return .white
        }
    }
}


//struct FileTailView: View {
//    @ObservedObject var fileWatcher: FileWatcher
//
//    var body: some View {
//        ScrollViewReader { proxy in
//            ScrollView {
//                LazyVStack(alignment: .leading, spacing: 4) {
//                    ForEach(Array(fileWatcher.lines.enumerated().reversed()), id: \.offset) { index, line in
//                        Text(line)
//                            .font(.system(.body, design: .monospaced))
//                            .foregroundColor(.green)
//                            .padding(.horizontal, 4)
//                            .id(index)
//                    }
//                }
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .padding(.vertical, 8)
//                .background(Color.black)
//            }
//            .onChange(of: fileWatcher.lines.count) { _ in
//                if let lastIndex = fileWatcher.lines.indices.last {
//                    withAnimation(.easeInOut(duration: 0.3)) {
//                        proxy.scrollTo(lastIndex, anchor: .top)
//                    }
//                }
//            }
//        }
//    }
//}
