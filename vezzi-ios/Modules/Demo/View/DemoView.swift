//
//  DemoView.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 01.11.2026.
//

import SwiftUI

/// View — внешний вид экрана: изображение, тексты, цвета и отступы.
/// Данные приходят через ViewModel; напрямую к Model экран не обращается.
struct DemoView: View {
    
    // Модель передаётся извне. @ObservedObject подписывает этот экран
    // на её изменения, но не создаёт модель и не управляет её временем жизни.
    @ObservedObject private var viewModel: DemoViewModel

    init(viewModel: DemoViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: Const.contentSpacing) {
            // Декоративное изображение принадлежит слою View.
            // Каталог ресурсов сам выбирает светлый или тёмный вариант.
            Image.Demo.main
                .resizable()
                .scaledToFit()
            
            textStack

            // @ObservedObject даёт доступ к binding через знак $.
            // Без $ передали бы только Bool. С $ передаём связь для чтения и записи: переключатель меняет isSubtitleVisible во ViewModel.
            DemoSubtitleToggle(
                title: viewModel.subtitleToggleTitle,
                isOn: $viewModel.isSubtitleVisible
            )
            .padding(.horizontal, Const.toggleHorizontalPadding)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Background.primary.ignoresSafeArea())
    }
    
    private var textStack: some View {
        VStack(spacing: Const.textSpacing) {
            Text(viewModel.title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.Label.primary)
            
            // Toggle меняет значение через binding, а @Published уведомляет
            // экран об изменении. SwiftUI заново вычисляет body, поэтому
            // подзаголовок появляется или исчезает.
            if viewModel.isSubtitleVisible {
                Text(viewModel.subtitle)
                    .font(.body)
                    .foregroundStyle(Color.Label.secondary)
            }
        }
    }
}

// MARK: - Const

private enum Const {
    static let contentSpacing: CGFloat = 24
    static let textSpacing: CGFloat = 12
    static let toggleHorizontalPadding: CGFloat = 24
}

// MARK: - Preview

#Preview("Light") {
    DemoView(viewModel: DemoViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    DemoView(viewModel: DemoViewModel())
        .preferredColorScheme(.dark)
}
