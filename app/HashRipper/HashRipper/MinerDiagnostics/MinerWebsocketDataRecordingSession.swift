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

    private func setupMessageForwarding() {
        Task {
            (await websocketClient.messagePublisher)
//            messageSubscription = publisher
                .filter({ !$0.isEmpty })
                .sink { [weak self] message in
                    self?.messageSubject.send(message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .store(in: &cancellables)

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
        let fileName = "\(Self.filenameDateFormatter.string(from: Date()))-\(minerHostName)-websocket-data.txt"
        let fileUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        Logger.sessionLogger.debug("Starting websocket data recording to \(fileUrl)")
        self.recordingFileWriter = .init(fileURL: fileUrl)
        self.recordingFileWriter?.startLogging(from: messagePublisher)
        self.state = .recording(file: fileUrl)
        recordingStateSubject.send(state)
        await self.websocketClient.connect(to: websocketUrl)
    }

    func stopRecording() async {
        Logger.sessionLogger.debug("Stopping websocket data recording")
        self.state = .idle
        await self.websocketClient.close()
        self.recordingFileWriter?.stopLogging()
        self.recordingFileWriter = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        recordingStateSubject.send(state)
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
        if let data = message.data(using: .utf8) {
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
