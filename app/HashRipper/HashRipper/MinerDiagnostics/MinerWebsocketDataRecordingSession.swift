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

    private var websocketClient: AxeOSWebsocketClient
    private var cancellables: Set<AnyCancellable> = []

    // Reconnection configuration
    private var reconnectAttempt: Int = 0
    private let maxReconnectAttempts: Int = 10
    private let reconnectBaseDelay: TimeInterval = 5
    private let reconnectMaxDelay: TimeInterval = 60
    private var reconnectTask: Task<Void, Never>?

    init(minerHostName: String, minerIpAddress: String, websocketClient: AxeOSWebsocketClient) {
        self.minerHostName = minerHostName
        self.minerIpAddress = minerIpAddress
        self.websocketClient = AxeOSWebsocketClient()
        self.websocketUrl = URL(string: "ws://\(minerIpAddress)/api/ws")!
    }

    private var connectionStateCancellable: AnyCancellable?
    private var recordingFileWriter: FileLogger?
    private var messageForwardingCancellable: AnyCancellable?

    private func setupSubscriptions() {
        Logger.sessionLogger.debug("Setting up subscriptions for \(self.minerIpAddress)")

        Task {
            // Subscribe to connection state changes
            connectionStateCancellable = await websocketClient.connectionStatePublisher
                .sink { [weak self] state in
                    guard let self = self else { return }
                    self.handleConnectionStateChange(state)
                }

            // Subscribe to messages
            messageForwardingCancellable = await websocketClient.messagePublisher
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

            Logger.sessionLogger.debug("Subscriptions established for \(self.minerIpAddress)")
        }
    }

    private func handleConnectionStateChange(_ state: WebSocketConnectionState) {
        switch state {
        case .connected:
            Logger.sessionLogger.info("WebSocket connected for \(self.minerIpAddress)")
            reconnectAttempt = 0  // Reset on successful connection
        case .failed(let reason):
            Logger.sessionLogger.warning("WebSocket connection failed for \(self.minerIpAddress): \(reason)")
            // Only attempt reconnect if we're supposed to be recording
            if isRecording() {
                scheduleReconnect()
            }
        case .disconnected:
            Logger.sessionLogger.debug("WebSocket disconnected for \(self.minerIpAddress)")
        case .reconnecting, .connecting:
            break
        }
    }

    private func scheduleReconnect() {
        guard reconnectAttempt < maxReconnectAttempts else {
            Logger.sessionLogger.error("Max reconnect attempts (\(self.maxReconnectAttempts)) reached for \(self.minerIpAddress), giving up")
            return
        }

        reconnectAttempt += 1
        let delay = min(reconnectBaseDelay * pow(2.0, Double(reconnectAttempt - 1)), reconnectMaxDelay)

        Logger.sessionLogger.info("Scheduling reconnect \(self.reconnectAttempt)/\(self.maxReconnectAttempts) for \(self.minerIpAddress) in \(Int(delay))s")

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self = self else { return }

            try? await Task.sleep(for: .seconds(delay))

            guard !Task.isCancelled else {
                Logger.sessionLogger.debug("Reconnect task cancelled for \(self.minerIpAddress)")
                return
            }

            // Only reconnect if still recording
            guard self.isRecording() else {
                Logger.sessionLogger.debug("Not reconnecting - no longer recording for \(self.minerIpAddress)")
                return
            }

            await self.performReconnect()
        }
    }

    private func performReconnect() async {
        Logger.sessionLogger.info("Performing reconnect for \(self.minerIpAddress), attempt \(self.reconnectAttempt)")

        // Close old client
        await websocketClient.close()

        // Cancel old subscriptions
        connectionStateCancellable?.cancel()
        messageForwardingCancellable?.cancel()

        // Create fresh client
        websocketClient = AxeOSWebsocketClient()

        // Setup new subscriptions
        setupSubscriptions()

        // Give subscriptions time to establish
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Connect
        Logger.sessionLogger.debug("Connecting new websocket client for \(self.minerIpAddress)")
        await websocketClient.connect(to: websocketUrl)
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

        // Reset reconnect state
        reconnectAttempt = 0
        reconnectTask?.cancel()

        // Setup subscriptions for this client
        setupSubscriptions()

        // Give subscriptions time to establish
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Don't create file by default - user toggles file writing
        let newState: RecordingState = .recording(file: nil)
        lock.perform { _state = newState }
        recordingStateSubject.send(newState)

        Logger.sessionLogger.debug("Connecting websocket to \(self.websocketUrl)")
        await websocketClient.connect(to: websocketUrl)
        Logger.sessionLogger.debug("Websocket connect() returned for \(self.minerIpAddress)")
    }

    func stopRecording() async {
        Logger.sessionLogger.debug("stopRecording() called for \(self.minerIpAddress), current state: \(String(describing: self.state))")

        // Cancel any pending reconnect
        reconnectTask?.cancel()
        reconnectTask = nil

        // Stop file writing if enabled
        if isWritingToFile {
            stopFileWriting()
        }

        lock.perform { _state = .idle }

        Logger.sessionLogger.debug("Closing websocket for \(self.minerIpAddress)")
        await websocketClient.close()
        Logger.sessionLogger.debug("Websocket closed for \(self.minerIpAddress)")

        // Cancel subscriptions
        connectionStateCancellable?.cancel()
        connectionStateCancellable = nil
        messageForwardingCancellable?.cancel()
        messageForwardingCancellable = nil

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
