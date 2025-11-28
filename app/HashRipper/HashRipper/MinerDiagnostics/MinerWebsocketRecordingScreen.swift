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
                        label: { Text("Start websocket data capture") }
                    )
                }
                VStack {
                    Spacer()
                }.background(Color.black)
                    .padding(12)
            case .recording(let file):
                HStack {
                    Text("Recording to \(file)")
                    Button(
                        action: {
                            showInFinder(fileURL: file)
                        },
                        label: {
                            Text("Show in Finder")
                        }
                    )
                }
                WebsocketMessagesView(viewModel: viewModel)
                    .padding(12)
                Button(
                    action: {
                        Task { await viewModel.session.stopRecording() }
                    },
                    label: { Text("Stop recording") }
                )
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
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


class MinerSelectionViewModel: ObservableObject, Identifiable {
    var id: String { minerIpAddress }

    @Published var isRecording: Bool = false
    var cancellables: Set<AnyCancellable> = []
    @Published var recordingState: MinerWebsocketDataRecordingSession.RecordingState
    @Published var websocketMessages: [String] = []

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

        session.recordingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self = self else { return }
                Logger.viewModelLogger.debug("recordingPublisher received state: \(String(describing: newState)) for \(self.minerIpAddress)")
                self.recordingState = newState
                self.isRecording = newState != .idle
            }
            .store(in: &cancellables)

        session.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.websocketMessages.append(message)
            }
            .store(in: &cancellables)
    }

    deinit {
        Logger.viewModelLogger.debug("MinerSelectionViewModel deinit for \(self.minerIpAddress)")
    }

    func clearMessages() {
        websocketMessages.removeAll()
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(viewModel.websocketMessages.enumerated()), id: \.0) { index, message in
                        Text(message)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 4)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onChange(of: viewModel.websocketMessages.count) { _ in
                if let lastIndex = viewModel.websocketMessages.indices.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
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
