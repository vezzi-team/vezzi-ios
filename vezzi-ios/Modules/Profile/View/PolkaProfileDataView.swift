//
//  PolkaProfileDataView.swift
//  vezzi-ios
//
//  Created by Anton on 16.11.2026.
//

import SwiftUI
import UIKit
import UserNotifications

struct PolkaProfileDataView: View {
    let name: String
    let email: String
    let phone: String
    let onTab: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            PolkaScreenHeader(title: "Данные") { dismiss() }
            ScrollView {
                VStack(spacing: 12) {
                    field("Имя", value: name)
                    field("Электронная почта", value: email)
                    field("Номер телефона", value: phone)
                }.padding(16)
            }
        }
        .background(PolkaPalette.background)
        .toolbar(.hidden, for: .navigationBar) }
    }

    private func field(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.body).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
