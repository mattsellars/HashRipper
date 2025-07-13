//
//  TextInputField.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct TextInputField: View {
    @Binding var text: String
    var title: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }
    var body: some View {
        ZStack {
            Text(title)
                .foregroundColor(text.isEmpty ? Color(.placeholderTextColor) : Color.accentColor)
                .offset(y: text.isEmpty ? 0 : -25)
                .scaleEffect(text.isEmpty ? 1 : 0.75, anchor: .leading)
            TextField("", text: $text)
        }
        .padding(.top, 15)
        .animation(.default)
    }
}
