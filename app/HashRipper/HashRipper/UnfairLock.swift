//
//  UnfairLock.swift
//  HashRipper
//
//  Created by Matt Sellars
//


import Foundation

// os_unfair_lock safely used via Swift (re: http://www.russbishop.net/the-law)
public final class UnfairLock {
    private let lock: os_unfair_lock_t

    public init() {
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deallocate()
    }

    @discardableResult
    public func perform<R>(guardedTask: () throws -> R) rethrows -> R {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return try guardedTask()
    }
}
