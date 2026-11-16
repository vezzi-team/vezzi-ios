import SwiftUI
import UIKit
import UserNotifications

struct AddressesView: View {
    @State private var draft: [PolkaAddress]
    @State private var editing: PolkaAddress?
    let onSave: ([PolkaAddress]) -> Void
    @Environment(\.dismiss) private var dismiss

    init(addresses: [PolkaAddress], onSave: @escaping ([PolkaAddress]) -> Void) {
        _draft = State(initialValue: addresses)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 20) {
            PolkaSheetHeader(title: "Мои адреса", onClose: { dismiss() }, onSave: {
                onSave(draft)
                dismiss()
            })
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 0) {
                        ForEach(Array(draft.enumerated()), id: \.element.id) { index, address in
                            Button { editing = address } label: {
                                HStack(spacing: 24) {
                                    Image(systemName: address.icon).font(.title3).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(address.title)
                                        Text(address.street).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                                }.padding(16)
                            }.buttonStyle(.plain)
                            if index < draft.count - 1 { Divider().padding(.leading, 62) }
                        }
                    }.background(.white, in: RoundedRectangle(cornerRadius: 18))
                    PolkaOrangeButton(title: "Добавить адрес") {
                        editing = PolkaAddress(title: "", street: "")
                    }.padding(.horizontal, 6)
                }.padding(.horizontal, 10)
            }
        }
        .padding(.top, 16)
        .sheet(item: $editing) { address in
            AddressEditor(address: address) { updated in
                if let index = draft.firstIndex(where: { $0.id == updated.id }) {
                    draft[index] = updated
                } else { draft.append(updated) }
            }
        }
    }
}

struct AddressEditor: View {
    @State var address: PolkaAddress
    let onSave: (PolkaAddress) -> Void
    @Environment(\.dismiss) private var dismiss
    private var valid: Bool {
        !address.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !address.street.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Название, например Дом", text: $address.title)
                TextField("Улица и номер дома", text: $address.street)
            }
            .navigationTitle("Адрес").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        address.title = address.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        address.street = address.street.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(address)
                        dismiss()
                    }.disabled(!valid)
                }
            }
        }
    }
}
