//
//  PageIndicator.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI


@Observable
class PageIndicatorViewModel {
    fileprivate var totalPages: Int
    fileprivate var currentPage: Int

    init(totalPages: Int) {
        self.totalPages = totalPages
        self.currentPage = 1
    }

    func nextPage() {
        if (currentPage < totalPages) {
            self.currentPage += 1
        }
    }

    func previousPage() {
        if (currentPage > 1) {
            self.currentPage -= 1
        }
    }
}

struct PageIndicator: View {
    @State var viewModel: PageIndicatorViewModel

    init(viewModel: PageIndicatorViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        HStack {
            ForEach(1...viewModel.totalPages, id: \.self) { page in
                Circle()
                    .frame(width: 4, height: 4)
                    .foregroundColor(page <= viewModel.currentPage ? .black.opacity(0.8) : .black.opacity(0.2))
            }
        }
    }
}
