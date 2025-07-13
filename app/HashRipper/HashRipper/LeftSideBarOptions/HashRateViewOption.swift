//
//  HashRateViewOption.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct HashRateViewOption: View {
    var body: some View {
        HStack(alignment: .center) {
            Image(
                systemName: "chart.bar.xaxis"
            )
//            .resizable()
            .aspectRatio(contentMode: .fit)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.orange, .mint)
            .frame(width: 24)
            Text("Hash Ops")
        }
    }
}
