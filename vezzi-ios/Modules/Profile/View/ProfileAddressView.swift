import SwiftUI

struct ProfileAddressView: View {
    @ObservedObject var list: ShoppingListRepository
    let location: any DeviceLocating
    @Environment(\.dismiss) private var dismiss
    @State private var showsMap = false

    var body: some View {
        ProfileCompactSheetContent {
            VStack(spacing: ProfileLayout.inset) {
                ProfileCard(minHeight: ProfileLayout.fieldHeight) {
                    Text(list.originAddress?.addressCapitalized ?? Texts.Routes.Settings.mapTitle)
                        .font(.body)
                }
                PrimaryActionButton(title: Texts.Profile.Addresses.edit) { showsMap = true }
                    .accessibilityIdentifier(AccessibilityID.Profile.editAddress)
            }
            .padding(ProfileLayout.inset)
        }
        .navigationTitle(Texts.Profile.Addresses.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ProfileSheetToolbar(onClose: { dismiss() }) }
        .fullScreenCover(isPresented: $showsMap) {
            LocationPickerView(coordinate: list.origin, options: list.routeOptions, address: list.originAddress,
                               location: location, onConfirm: list.setRoute)
        }
    }
}

#Preview {
    @Previewable @StateObject var list = ShoppingListRepository()
    NavigationStack { ProfileAddressView(list: list, location: DeviceLocationService()) }
        .task { list.setRoute(origin: .defaultOrigin, options: .init(), address: "Проспект Королёва, 34 к2") }
}
