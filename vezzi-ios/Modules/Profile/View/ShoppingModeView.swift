import SwiftUI
import UIKit
import UserNotifications

struct ShoppingModeView: View {
    @Binding var selection: PolkaShoppingMode
    @State private var draft: PolkaShoppingMode
    @Environment(\.dismiss) private var dismiss

    init(selection: Binding<PolkaShoppingMode>) {
        _selection = selection
        _draft = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 18) {
            PolkaSheetHeader(title: "Как покупать", onClose: { dismiss() }, onSave: {
                selection = draft
                dismiss()
            })
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(PolkaShoppingMode.allCases) { mode in
                        Button { draft = mode } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title).foregroundStyle(.primary)
                                Text(mode.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(22)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                            .overlay {
                                RoundedRectangle(cornerRadius: 17)
                                    .stroke(draft == mode ? PolkaPalette.orange : .clear, lineWidth: 1.5)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(draft == mode ? [.isSelected] : [])
                    }
                }.padding(.horizontal, 10)
            }
        }.padding(.top, 16)
    }
}
