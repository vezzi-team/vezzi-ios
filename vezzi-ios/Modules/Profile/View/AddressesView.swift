import SwiftUI

struct AddressesView: View {
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: AuthenticationSession) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Const.spacing) {
                if viewModel.addresses.isEmpty {
                    ProfileCard {
                        Text(Texts.Profile.Addresses.empty).appTextStyle(.appText)
                    }
                } else {
                    addressList
                }
                Button(action: viewModel.addAddress) {
                    Text(Texts.Profile.Addresses.add).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(.accentColor)
                .accessibilityIdentifier(AccessibilityID.Profile.addAddress)
                Text(Texts.Profile.Controls.temporary)
                    .appTextStyle(.caption).foregroundStyle(Color.Label.secondary)
            }.padding(Const.inset)
        }
        .foregroundStyle(Color.Label.primary)
        .background(Color.Background.primary)
        .navigationTitle(Texts.Profile.Addresses.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ProfileSheetToolbar(onClose: { dismiss() }, onSave: {
                if viewModel.saveAddresses() { dismiss() }
            })
        }
        .sheet(item: $viewModel.editingAddress) { address in
            ProfileAddressEditor(address: address, onSave: viewModel.updateAddress)
        }
    }

    private var addressList: some View {
        ProfileCard {
            VStack(spacing: .zero) {
                ForEach(viewModel.addresses) { address in
                    if address.id != viewModel.addresses.first?.id { Divider() }
                    Button { viewModel.editingAddress = address } label: {
                        ProfileRow(title: address.title, image: Image.System.profileLocation,
                                   subtitle: address.street)
                    }
                    .pressScaleEffect()
                    .accessibilityIdentifier(AccessibilityID.Profile.addressRow(address.id))
                }
            }
        }
    }

    private enum Const {
        static let spacing: CGFloat = 12
        static let inset: CGFloat = 16
    }
}

private struct ProfileAddressEditor: View {
    @State var address: ProfileAddress
    let onSave: (ProfileAddress) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Texts.Profile.Addresses.name, text: $address.title)
                        .accessibilityIdentifier(AccessibilityID.Profile.addressName)
                    TextField(Texts.Profile.Addresses.street, text: $address.street, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                        .accessibilityIdentifier(AccessibilityID.Profile.addressStreet)
                }
                .listRowBackground(Color.Background.secondary)
            }
            .scrollContentBackground(.hidden)
            .background(Color.Background.primary)
            .navigationTitle(Texts.Profile.Addresses.editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Texts.Authentication.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Texts.Profile.Controls.save) {
                        onSave(address.trimmed)
                        dismiss()
                    }
                    .disabled(!address.isValid)
                    .accessibilityIdentifier(AccessibilityID.Profile.saveAddress)
                }
            }
        }
    }
}

#Preview("Addresses — empty") {
    NavigationStack { AddressesView(session: .preview()) }
}
