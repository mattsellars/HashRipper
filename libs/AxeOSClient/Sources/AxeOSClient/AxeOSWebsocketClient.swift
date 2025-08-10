//
//  AxeOSWebsocketClient.swift
//  AxeOSClient
//
//  Created by Matt Sellars
//

import Combine
import Foundation
import OSLog

/// Wrap the socket in an `actor` so its state is thread-safe under Swift Concurrency.
public actor AxeOSWebsocketClient {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession

    private let messageSubject = PassthroughSubject<String, Never>()
    public var messagePublisher: AnyPublisher<String, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    public init() {
        // Use a background-friendly configuration if you need the socket
        // to work while your app is in the background. Otherwise `.default` is fine.
        session = URLSession(configuration: .default)
    }

    deinit {
        task?.cancel(with: .normalClosure, reason: nil)
    }
    /// Connect to the server and start the read loop.
    public func connect(to url: URL) async {
        // Cancel an existing connection if the caller reconnects
        task?.cancel(with: .goingAway, reason: nil)

        let newTask = session.webSocketTask(with: url)
        task = newTask
        newTask.resume()

        // Kick off a concurrent read loop
        Task { await readLoop(socket: newTask) }

        // Some servers require a ping every N seconds
        Task { await pingLoop(socket: newTask) }
    }

    /// Send a text message - I don't know if this is supported
    public func send(text: String) async throws {
        try await task?.send(.string(text))
    }

    /// Close cleanly
    public func close() {
        task?.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: – Private helpers

    private func readLoop(socket: URLSessionWebSocketTask) async {
        // Swift Concurrency lets us await messages in a simple loop
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    Logger.websocketsLogger.debug("[ws::received::text] \(text)")
                    self.messageSubject.send(text)
                case .data(let data):
                    Logger.websocketsLogger.debug("[ws::received::data] \(data.count) bytes")
                @unknown default:
                    break
                }
            } catch {
                print("Receive error: \(error)")
                break     // Exit the loop and let the caller decide what to do
            }
        }
    }

    private func pingLoop(socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            // Ignore failures – if the ping fails the read loop will error out soon after
            try? await socket.sendPingAsync()
        }
    }
}

extension URLSessionWebSocketTask {
    /// Async wrapper for pre-macOS-12 `sendPing(pongReceiveHandler:)`
    @available(macOS 10.15, *)
    func sendPingAsync() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.sendPing { error in
                if let error { cont.resume(throwing: error) }
                else        { cont.resume() }
            }
        }
    }
}

extension Logger {
    static let websocketsLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HashRipper", category: "AxeOSWebsocketClient")
}
