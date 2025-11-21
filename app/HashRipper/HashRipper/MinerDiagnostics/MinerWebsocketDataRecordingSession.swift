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

class MinerWebsocketDataRecordingSession {
    public enum RecordingState: Hashable {
        case idle
        case recording(file: URL)
    }

    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH:mm"
        return formatter
    }()

    public private(set) var state: RecordingState = .idle

    private let recordingStateSubject = PassthroughSubject<RecordingState, Never>()
    public var recordingPublisher: AnyPublisher<RecordingState, Never> {
        recordingStateSubject.eraseToAnyPublisher()
    }

    private let messageSubject = PassthroughSubject<String, Never>()
    public var messagePublisher: AnyPublisher<String, Never> {
        messageSubject.eraseToAnyPublisher()
    }

//    public let miner: Miner
    public let minerHostName: String
    public let minerIpAddress: String
    public let websocketUrl: URL

    public let websocketClient: AxeOSWebsocketClient
//    private var messageSubscription: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []

    init(minerHostName: String, minerIpAddress: String, websocketClient: AxeOSWebsocketClient) {
        self.minerHostName = minerHostName
        self.minerIpAddress = minerIpAddress
        self.websocketClient = AxeOSWebsocketClient()
        self.websocketUrl = URL(string: "ws://\(minerIpAddress)/api/ws")!
        setupMessageForwarding()
    }

    private var recordingFileWriter: FileLogger?
    private var messageForwardingCancellable: AnyCancellable?

    private func setupMessageForwarding() {
        Logger.sessionLogger.debug("Setting up message forwarding for \(self.minerIpAddress)")
        Task {
            messageForwardingCancellable = (await websocketClient.messagePublisher)
                .filter({ !$0.isEmpty })
                .sink { [weak self] message in
                    self?.messageSubject.send(message.trimmingCharacters(in: .whitespacesAndNewlines))
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

        let fileName = "\(Self.filenameDateFormatter.string(from: Date()))-\(minerHostName)-websocket-data.txt"
        let fileUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        Logger.sessionLogger.debug("Starting websocket data recording to \(fileUrl)")
        self.recordingFileWriter = .init(fileURL: fileUrl)
        self.recordingFileWriter?.startLogging(from: messagePublisher)
        self.state = .recording(file: fileUrl)
        recordingStateSubject.send(state)

        Logger.sessionLogger.debug("Connecting websocket to \(self.websocketUrl)")
        await self.websocketClient.connect(to: websocketUrl)
        Logger.sessionLogger.debug("Websocket connect() returned for \(self.minerIpAddress)")
    }

    func stopRecording() async {
        Logger.sessionLogger.debug("stopRecording() called for \(self.minerIpAddress), current state: \(String(describing: self.state))")
        self.state = .idle

        Logger.sessionLogger.debug("Closing websocket for \(self.minerIpAddress)")
        await self.websocketClient.close()
        Logger.sessionLogger.debug("Websocket closed for \(self.minerIpAddress)")

        self.recordingFileWriter?.stopLogging()
        self.recordingFileWriter = nil

        // Cancel message forwarding so it can be re-established on next recording
        messageForwardingCancellable?.cancel()
        messageForwardingCancellable = nil
        Logger.sessionLogger.debug("Message forwarding cancelled for \(self.minerIpAddress)")

        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        recordingStateSubject.send(state)
        Logger.sessionLogger.debug("stopRecording() completed for \(self.minerIpAddress)")
    }
}


class MinerWebsocketRecordingSessionRegistry {
    let accessLock = UnfairLock()
    private var sessionsByMinerIpAddress: [String: MinerWebsocketDataRecordingSession] = [:]

    static let shared: MinerWebsocketRecordingSessionRegistry = .init()

    private init() {}

    func getOrCreateRecordingSession(minerHostName: String, minerIpAddress: String) -> MinerWebsocketDataRecordingSession {
        return accessLock.perform {
            if let session = sessionsByMinerIpAddress[minerIpAddress] {
                return session
            }

            let session = MinerWebsocketDataRecordingSession(minerHostName: minerHostName, minerIpAddress: minerIpAddress, websocketClient: AxeOSWebsocketClient())
            sessionsByMinerIpAddress[minerIpAddress] = session
            return session
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
