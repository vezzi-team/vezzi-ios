//
//  DemoView.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 01.11.2026.
//

import SwiftUI

struct DemoView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(Texts.Demo.title)
        }
        .padding()
    }
}

#Preview {
    DemoView()
}
