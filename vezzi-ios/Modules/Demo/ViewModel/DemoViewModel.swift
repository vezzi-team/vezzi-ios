//
//  DemoViewModel.swift
//  vezzi-ios
//
//  Created by Roman Tverdohleb on 01.11.2026.
//

import Combine

/// ViewModel — связующее звено между данными и экраном.
/// Получает Model и предоставляет View всё необходимое для отображения.
/// ObservableObject позволяет View подписаться на изменения ViewModel.
final class DemoViewModel: ObservableObject {
    // Модель скрыта: View обращается только к свойствам ViewModel.
    private let model: DemoModel

    // Единственный источник состояния переключателя.
    // Это состояние интерфейса, поэтому оно находится во ViewModel.
    // @Published сообщает подписчикам об изменении значения.
    @Published var isSubtitleVisible = true

    var title: String {
        model.title
    }

    var subtitle: String {
        model.subtitle
    }

    var subtitleToggleTitle: String {
        Texts.Demo.showSubtitle
    }

    // По умолчанию используем существующие локализованные строки.
    // Можно передать другую модель, например для превью или тестов.
    init(model: DemoModel = DemoModel(
        title: Texts.Demo.title,
        subtitle: Texts.Demo.subtitle
    )) {
        self.model = model
    }
}
