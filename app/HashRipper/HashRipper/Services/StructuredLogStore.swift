//
//  StructuredLogStore.swift
//  HashRipper
//
//  Created by Claude Code
//

import Combine
import Foundation

actor StructuredLogStore {
    private var entries: [WebSocketLogEntry] = []
    private var maxEntries: Int

    private let entriesSubject = PassthroughSubject<[WebSocketLogEntry], Never>()
    nonisolated var entriesPublisher: AnyPublisher<[WebSocketLogEntry], Never> {
        entriesSubject.eraseToAnyPublisher()
    }

    init(maxEntries: Int? = nil) {
        self.maxEntries = maxEntries ?? AppSettings.shared.websocketLogBufferSize
    }

    func append(_ entry: WebSocketLogEntry) {
        entries.append(entry)

        // Trim old entries if we exceed max
        if entries.count > maxEntries {
            let removeCount = entries.count - maxEntries
            entries.removeFirst(removeCount)
        }

        // Publish updated entries
        entriesSubject.send(entries)
    }

    func clear() {
        entries.removeAll()
        entriesSubject.send(entries)
    }

    func getEntries() -> [WebSocketLogEntry] {
        return entries
    }

    func updateMaxEntries(_ newMax: Int) {
        maxEntries = newMax
        // Trim if necessary
        if entries.count > maxEntries {
            let removeCount = entries.count - maxEntries
            entries.removeFirst(removeCount)
            entriesSubject.send(entries)
        }
    }

    // Filtering methods
    func filter(
        level: WebSocketLogEntry.LogLevel? = nil,
        component: WebSocketLogEntry.LogComponent? = nil,
        category: WebSocketLogEntry.LogCategory? = nil,
        searchText: String? = nil
    ) -> [WebSocketLogEntry] {
        var filtered = entries

        if let level = level {
            filtered = filtered.filter { $0.level == level }
        }

        if let component = component {
            filtered = filtered.filter { $0.component == component }
        }

        if let category = category {
            filtered = filtered.filter { $0.component.category == category }
        }

        if let searchText = searchText, !searchText.isEmpty {
            filtered = filtered.filter {
                $0.message.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    // Get all unique components that have appeared in logs
    func uniqueComponents() -> [WebSocketLogEntry.LogComponent] {
        var seen = Set<WebSocketLogEntry.LogComponent>()
        var components: [WebSocketLogEntry.LogComponent] = []

        for entry in entries {
            if !seen.contains(entry.component) {
                seen.insert(entry.component)
                components.append(entry.component)
            }
        }

        return components.sorted { $0.displayName < $1.displayName }
    }

    // Grouping methods
    func groupedByComponent() -> [WebSocketLogEntry.LogComponent: [WebSocketLogEntry]] {
        Dictionary(grouping: entries, by: { $0.component })
    }

    func groupedByCategory() -> [WebSocketLogEntry.LogCategory: [WebSocketLogEntry]] {
        Dictionary(grouping: entries, by: { $0.component.category })
    }

    // Get statistics about dynamic components
    func dynamicComponentStats() -> [(name: String, count: Int)] {
        let dynamicEntries = entries.filter {
            if case .dynamic = $0.component { return true }
            return false
        }

        let grouped = Dictionary(grouping: dynamicEntries) { entry -> String in
            if case .dynamic(let value) = entry.component {
                return value
            }
            return ""
        }

        return grouped.map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}
