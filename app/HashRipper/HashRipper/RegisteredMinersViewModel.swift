//
//  RegisteredMinersViewModel.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

@Observable
class RegisteredMinersViewModel {
    let modelContainer: ModelContainer

    var miners: [MinerUpdate] = []

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }


}
