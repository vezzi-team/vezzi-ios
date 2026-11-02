import SwiftUI

struct StoresView: View {
    var body: some View {
        Color.Background.primary
            .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        StoresView()
            .navigationTitle(Texts.Tabbar.stores)
    }
}
