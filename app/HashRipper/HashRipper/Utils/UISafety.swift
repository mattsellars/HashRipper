//
//  UISafety.swift
//  HashRipper
//
import Foundation
func EnsureUISafe(_ block: @escaping () -> Void) {
    Thread.isMainThread ? block() : DispatchQueue.main.async(execute: block)
}
