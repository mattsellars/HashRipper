//
//  AxeOSWebsocketClient.swift
//  AxeOSClient
//
//  Created by Matt Sellars
//

import Combine
import Foundation
import OSLog

public enum WebSocketConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(reason: String)
}

/// Wrap the socket in an `actor` so its state is thread-safe under Swift Concurrency.
public actor AxeOSWebsocketClient {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private var currentURL: URL?

    // Connection state
    private var _connectionState: WebSocketConnectionState = .disconnected
    public var connectionState: WebSocketConnectionState { _connectionState }

    private let connectionStateSubject = PassthroughSubject<WebSocketConnectionState, Never>()
    public var connectionStatePublisher: AnyPublisher<WebSocketConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }

    private let messageSubject = PassthroughSubject<String, Never>()
    public var messagePublisher: AnyPublisher<String, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    // Configuration
    public var autoReconnect: Bool = false
    public var maxReconnectAttempts: Int = 10
    public var reconnectBaseDelay: TimeInterval = 5  // Start with 5 seconds
    public var reconnectMaxDelay: TimeInterval = 60  // Cap at 60 seconds
    public var pingInterval: TimeInterval = 15
    public var maxConsecutivePingFailures: Int = 3

    /// Enable or disable auto-reconnect
    public func setAutoReconnect(_ enabled: Bool, maxAttempts: Int = 10) {
        autoReconnect = enabled
        maxReconnectAttempts = maxAttempts
    }

    // Internal state
    private var consecutivePingFailures: Int = 0
    private var reconnectAttempt: Int = 0
    private var readLoopTask: Task<Void, Never>?
    private var pingLoopTask: Task<Void, Never>?

    public init() {
        session = URLSession(configuration: .default)
    }

    deinit {
        task?.cancel(with: .normalClosure, reason: nil)
    }

    /// Connect to the server and start the read loop.
    public func connect(to url: URL) async {
        Logger.websocketsLogger.debug("connect() called for \(url.absoluteString)")

        currentURL = url
        reconnectAttempt = 0
        await connectInternal(to: url)
    }

    private func connectInternal(to url: URL) async {
        Logger.websocketsLogger.debug("connectInternal starting for \(url.host ?? "unknown")")

        // Cancel existing loops
        readLoopTask?.cancel()
        pingLoopTask?.cancel()

        // Cancel an existing connection if the caller reconnects
        if task != nil {
            Logger.websocketsLogger.debug("Cancelling existing task before reconnecting")
            task?.cancel(with: .goingAway, reason: nil)
        }

        setConnectionState(.connecting)

        let newTask = session.webSocketTask(with: url)
        task = newTask
        consecutivePingFailures = 0
        newTask.resume()

        Logger.websocketsLogger.debug("WebSocket task resumed for \(url.host ?? "unknown"), starting read/ping loops")
        setConnectionState(.connected)

        // Kick off a concurrent read loop
        readLoopTask = Task { [weak self] in
            await self?.readLoop(socket: newTask)
        }

        // Some servers require a ping every N seconds
        pingLoopTask = Task { [weak self] in
            await self?.pingLoop(socket: newTask)
        }
    }

    /// Send a text message
    public func send(text: String) async throws {
        try await task?.send(.string(text))
    }

    /// Close cleanly
    public func close() {
        Logger.websocketsLogger.debug("close() called, task exists: \(self.task != nil)")

        readLoopTask?.cancel()
        pingLoopTask?.cancel()
        readLoopTask = nil
        pingLoopTask = nil

        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        currentURL = nil

        setConnectionState(.disconnected)
        Logger.websocketsLogger.debug("WebSocket task cancelled and cleared")
    }

    private func setConnectionState(_ state: WebSocketConnectionState) {
        _connectionState = state
        connectionStateSubject.send(state)
    }

    // MARK: – Private helpers

    private func readLoop(socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled && socket.state == .running {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    self.messageSubject.send(text)
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled else { break }
                Logger.websocketsLogger.error("WebSocket receive error: \(error.localizedDescription)")
                await handleConnectionLost(reason: error.localizedDescription)
                break
            }
        }
    }

    private func pingLoop(socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled && socket.state == .running {
            try? await Task.sleep(for: .seconds(pingInterval))
            guard !Task.isCancelled && socket.state == .running else { break }

            do {
                try await socket.sendPingAsync()
                // Reset failure counter on success
                consecutivePingFailures = 0
            } catch {
                guard !Task.isCancelled else { break }
                consecutivePingFailures += 1
                Logger.websocketsLogger.warning("Ping failed (\(self.consecutivePingFailures)/\(self.maxConsecutivePingFailures)): \(error.localizedDescription)")

                if consecutivePingFailures >= maxConsecutivePingFailures {
                    Logger.websocketsLogger.error("Max ping failures reached, closing connection")
                    await handleConnectionLost(reason: "Ping timeout after \(maxConsecutivePingFailures) failures")
                    break
                }
            }
        }
    }

    private func handleConnectionLost(reason: String) async {
        Logger.websocketsLogger.debug("handleConnectionLost called: \(reason), autoReconnect=\(self.autoReconnect), attempt=\(self.reconnectAttempt)/\(self.maxReconnectAttempts)")

        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil

        readLoopTask?.cancel()
        pingLoopTask?.cancel()

        if autoReconnect, let url = currentURL, reconnectAttempt < maxReconnectAttempts {
            reconnectAttempt += 1
            setConnectionState(.reconnecting(attempt: reconnectAttempt))

            // Exponential backoff: 5s, 10s, 20s, 40s, 60s (capped)
            let delay = min(reconnectBaseDelay * pow(2.0, Double(reconnectAttempt - 1)), reconnectMaxDelay)
            Logger.websocketsLogger.info("Reconnect attempt \(self.reconnectAttempt)/\(self.maxReconnectAttempts) for \(url.host ?? "unknown") in \(Int(delay))s")

            try? await Task.sleep(for: .seconds(delay))

            guard !Task.isCancelled else {
                Logger.websocketsLogger.debug("Reconnect cancelled during sleep")
                return
            }

            Logger.websocketsLogger.debug("Attempting reconnect to \(url.absoluteString)")
            await connectInternal(to: url)
        } else if autoReconnect && reconnectAttempt >= maxReconnectAttempts {
            setConnectionState(.failed(reason: "Max reconnect attempts reached after \(maxReconnectAttempts) tries"))
            Logger.websocketsLogger.error("Max reconnect attempts (\(self.maxReconnectAttempts)) reached for \(self.currentURL?.host ?? "unknown"), giving up")
        } else {
            Logger.websocketsLogger.debug("Not reconnecting: autoReconnect=\(self.autoReconnect)")
            setConnectionState(.failed(reason: reason))
        }
    }
}

extension URLSessionWebSocketTask {
    /// Async wrapper for `sendPing(pongReceiveHandler:)`
    @available(macOS 10.15, *)
    func sendPingAsync() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Use a class to track whether continuation was already resumed
            // (callback can be invoked multiple times under error conditions)
            final class ResumeOnce: @unchecked Sendable {
                private var resumed = false
                private let lock = NSLock()

                func resume(with cont: CheckedContinuation<Void, Error>, error: Error?) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true

                    if let error = error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }

            let once = ResumeOnce()
            self.sendPing { error in
                once.resume(with: cont, error: error)
            }
        }
    }
}

extension Logger {
    static let websocketsLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HashRipper", category: "AxeOSWebsocketClient")
}
