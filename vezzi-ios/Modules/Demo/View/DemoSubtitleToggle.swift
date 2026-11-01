//
//  DemoSubtitleToggle.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 01.11.2026.
//

import SwiftUI

/// Дочерняя View показывает, как передавать состояние через @Binding.
struct DemoSubtitleToggle: View {
    let title: String

    // @Binding не хранит отдельный Bool: читает и изменяет значение,
    // переданное родителем. Дочерней View не нужно знать о ViewModel.
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .tint(.accentColor)
            .foregroundStyle(Color.Label.primary)
            .multilineTextAlignment(.leading)
    }
}

#Preview {
    // Превью хранит состояние, а переключатель меняет его через binding.
    @Previewable @State var isOn = true

    DemoSubtitleToggle(title: "Demo", isOn: $isOn)
        .padding()
}
