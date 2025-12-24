//
//  MinerWebsocketDataRecordingSession.swift
//  HashRipper
//
//  Created by Matt Sellars on 7/30/25.
//

import Combine
import Foundation
import AxeOSClient
import OSLog

class MinerWebsocketDataRecordingSession: ObservableObject {
    public enum RecordingState: Hashable {
        case idle
        case recording(file: URL?)  // File is optional now
    }

    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH:mm:ss"  // Added seconds
        return formatter
    }()

    private let lock = UnfairLock()
    private var _state: RecordingState = .idle
    public var state: RecordingState {
        lock.perform { _state }
    }

    private let recordingStateSubject = PassthroughSubject<RecordingState, Never>()
    public var recordingPublisher: AnyPublisher<RecordingState, Never> {
        recordingStateSubject.eraseToAnyPublisher()
    }

    private let messageSubject = PassthroughSubject<String, Never>()
    public var messagePublisher: AnyPublisher<String, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    // Structured logging components
    private let parser = WebSocketLogParser()

    private let structuredLogSubject = PassthroughSubject<WebSocketLogEntry, Never>()
    public var structuredLogPublisher: AnyPublisher<WebSocketLogEntry, Never> {
        structuredLogSubject.eraseToAnyPublisher()
    }

    // File writing configuration - updated on MainActor for UI
    @Published public var isWritingToFile: Bool = false
    @Published public var currentFileURL: URL?

    public let minerHostName: String
    public let minerIpAddress: String
    public let websocketUrl: URL

    public let websocketClient: AxeOSWebsocketClient
    private var cancellables: Set<AnyCancellable> = []

    init(minerHostName: String, minerIpAddress: String, websocketClient: AxeOSWebsocketClient) {
        self.minerHostName = minerHostName
        self.minerIpAddress = minerIpAddress
        self.websocketClient = AxeOSWebsocketClient()
        self.websocketUrl = URL(string: "ws://\(minerIpAddress)/api/ws")!
        setupMessageForwarding()
        setupConnectionStateMonitoring()
    }

    private var connectionStateCancellable: AnyCancellable?

    private func setupConnectionStateMonitoring() {
        Task {
            connectionStateCancellable = await websocketClient.connectionStatePublisher
                .sink { [weak self] state in
                    guard let self = self else { return }
                    switch state {
                    case .failed(let reason):
                        Logger.sessionLogger.warning("WebSocket connection failed for \(self.minerIpAddress): \(reason)")
                    case .reconnecting(let attempt):
                        Logger.sessionLogger.info("WebSocket reconnecting for \(self.minerIpAddress), attempt \(attempt)")
                    case .connected:
                        Logger.sessionLogger.info("WebSocket connected for \(self.minerIpAddress)")
                    case .disconnected:
                        Logger.sessionLogger.debug("WebSocket disconnected for \(self.minerIpAddress)")
                    case .connecting:
                        break
                    }
                }
        }
    }

    private var recordingFileWriter: FileLogger?
    private var messageForwardingCancellable: AnyCancellable?

    private func setupMessageForwarding() {
        Logger.sessionLogger.debug("Setting up message forwarding for \(self.minerIpAddress)")
        Task {
            messageForwardingCancellable = (await websocketClient.messagePublisher)
                .filter({ !$0.isEmpty })
                .sink { [weak self] message in
                    guard let self = self else { return }

                    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Send raw message
                    self.messageSubject.send(trimmed)

                    // Parse and publish structured log
                    Task {
                        if let entry = await self.parser.parse(trimmed) {
                            self.structuredLogSubject.send(entry)
                        }
                    }
                }
            Logger.sessionLogger.debug("Message forwarding subscription established for \(self.minerIpAddress)")
        }
    }

    func isRecording() -> Bool {
        switch state {
        case .recording:
            return true
        default:
            return false
        }
    }

    func startRecording() async {
        Logger.sessionLogger.debug("startRecording() called for \(self.minerIpAddress), current state: \(String(describing: self.state))")

        // Re-setup message forwarding if it was cancelled
        if messageForwardingCancellable == nil {
            Logger.sessionLogger.debug("Message forwarding cancellable is nil, re-establishing for \(self.minerIpAddress)")
            setupMessageForwarding()
            // Give the async setup a moment to complete
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Don't create file by default - user toggles file writing
        let newState: RecordingState = .recording(file: nil)
        lock.perform { _state = newState }
        recordingStateSubject.send(newState)

        // Enable auto-reconnect for pool monitoring reliability
        await websocketClient.setAutoReconnect(true)

        Logger.sessionLogger.debug("Connecting websocket to \(self.websocketUrl)")
        await self.websocketClient.connect(to: websocketUrl)
        Logger.sessionLogger.debug("Websocket connect() returned for \(self.minerIpAddress)")
    }

    func stopRecording() async {
        Logger.sessionLogger.debug("stopRecording() called for \(self.minerIpAddress), current state: \(String(describing: self.state))")

        // Stop file writing if enabled
        if isWritingToFile {
            stopFileWriting()
        }

        lock.perform { _state = .idle }

        // Disable auto-reconnect before closing to prevent reconnection attempts
        await websocketClient.setAutoReconnect(false)

        Logger.sessionLogger.debug("Closing websocket for \(self.minerIpAddress)")
        await self.websocketClient.close()
        Logger.sessionLogger.debug("Websocket closed for \(self.minerIpAddress)")

        // Cancel message forwarding so it can be re-established on next recording
        messageForwardingCancellable?.cancel()
        messageForwardingCancellable = nil
        Logger.sessionLogger.debug("Message forwarding cancelled for \(self.minerIpAddress)")

        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        recordingStateSubject.send(.idle)
        Logger.sessionLogger.debug("stopRecording() completed for \(self.minerIpAddress)")
    }

    // MARK: - File Writing

    func toggleFileWriting() async {
        if isWritingToFile {
            stopFileWriting()
        } else {
            startFileWriting()
        }
    }

    private func startFileWriting() {
        guard !isWritingToFile else { return }

        // Generate unique filename with seconds
        let fileName = generateUniqueFileName()
        let fileUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)

        Logger.sessionLogger.debug("Starting file writing to \(fileUrl)")

        // Create file logger
        self.recordingFileWriter = .init(fileURL: fileUrl)

        // Start logging new messages
        self.recordingFileWriter?.startLogging(from: messagePublisher)

        // Update state
        let newState: RecordingState = .recording(file: fileUrl)
        lock.perform { _state = newState }
        recordingStateSubject.send(newState)

        // Update @Published on main thread for UI
        Task { @MainActor [weak self] in
            self?.currentFileURL = fileUrl
            self?.isWritingToFile = true
        }

        Logger.sessionLogger.debug("File writing started")
    }

    private func stopFileWriting() {
        guard isWritingToFile else { return }

        Logger.sessionLogger.debug("Stopping file writing")

        self.recordingFileWriter?.stopLogging()
        self.recordingFileWriter = nil

        // Update state (recording but no file)
        let newState: RecordingState = .recording(file: nil)
        lock.perform { _state = newState }
        recordingStateSubject.send(newState)

        // Update @Published on main thread for UI
        Task { @MainActor [weak self] in
            self?.currentFileURL = nil
            self?.isWritingToFile = false
        }

        Logger.sessionLogger.debug("File writing stopped")
    }

    private func generateUniqueFileName() -> String {
        let formatter = Self.filenameDateFormatter
        return "\(formatter.string(from: Date()))-\(minerHostName)-websocket-data.txt"
    }
}


class MinerWebsocketRecordingSessionRegistry {
    private let accessLock = UnfairLock()
    private var sessionsByMinerIpAddress: [String: MinerWebsocketDataRecordingSession] = [:]
    private var recordingStateSubscriptions: [String: AnyCancellable] = [:]

    static let shared: MinerWebsocketRecordingSessionRegistry = .init()

    // Notification when a session starts recording
    private let sessionRecordingStartedSubject = PassthroughSubject<MinerWebsocketDataRecordingSession, Never>()
    var sessionRecordingStartedPublisher: AnyPublisher<MinerWebsocketDataRecordingSession, Never> {
        sessionRecordingStartedSubject.eraseToAnyPublisher()
    }

    // Notification when a session stops recording
    private let sessionRecordingStoppedSubject = PassthroughSubject<String, Never>()  // IP address
    var sessionRecordingStoppedPublisher: AnyPublisher<String, Never> {
        sessionRecordingStoppedSubject.eraseToAnyPublisher()
    }

    private init() {}

    func getOrCreateRecordingSession(minerHostName: String, minerIpAddress: String) -> MinerWebsocketDataRecordingSession {
        return accessLock.perform {
            if let session = sessionsByMinerIpAddress[minerIpAddress] {
                return session
            }

            let session = MinerWebsocketDataRecordingSession(minerHostName: minerHostName, minerIpAddress: minerIpAddress, websocketClient: AxeOSWebsocketClient())
            sessionsByMinerIpAddress[minerIpAddress] = session

            // Subscribe to recording state changes
            let subscription = session.recordingPublisher
                .sink { [weak self, weak session] state in
                    guard let self = self, let session = session else { return }
                    switch state {
                    case .recording:
                        self.sessionRecordingStartedSubject.send(session)
                    case .idle:
                        self.sessionRecordingStoppedSubject.send(minerIpAddress)
                    }
                }
            recordingStateSubscriptions[minerIpAddress] = subscription

            return session
        }
    }

    /// Get all currently recording sessions
    func getActiveRecordingSessions() -> [MinerWebsocketDataRecordingSession] {
        accessLock.perform {
            sessionsByMinerIpAddress.values.filter { $0.isRecording() }
        }
    }

    /// Get session by IP address
    func getSession(forIP ipAddress: String) -> MinerWebsocketDataRecordingSession? {
        accessLock.perform {
            sessionsByMinerIpAddress[ipAddress]
        }
    }
}

fileprivate extension Logger {
    static let sessionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HashRipper", category: "MinerWebsocketDataRecordingSession")
}


class FileLogger {
    private let fileURL: URL
    private var cancellable: AnyCancellable?
    let serialQueue = DispatchQueue(label: "FileLogger")

    convenience init?(fileName: String = "websocket_output.txt", inSearchPathDir: FileManager.SearchPathDirectory) {
        guard
            let documentsDirectory = FileManager.default.urls(for: inSearchPathDir, in: .userDomainMask).first
        else {
            return nil
        }

        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        self.init(fileURL: fileURL)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func startLogging(from publisher: AnyPublisher<String, Never>) {
        cancellable = publisher
            .sink { [weak self] message in
                guard let self = self else { return }
                serialQueue.async {
                    self.writeToFile(message)
                }
            }
    }

    func stopLogging() {
        cancellable?.cancel()
    }

    private func writeToFile(_ message: String) {
        if let data = "\(message)\n".data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try! data.write(to: fileURL)
            }
        }
    }
}
