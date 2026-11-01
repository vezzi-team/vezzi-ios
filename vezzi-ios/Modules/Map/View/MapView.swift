import SwiftUI

struct MapView: View {
    var body: some View {
        Color.Background.primary
            .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        MapView()
            .navigationTitle(Texts.Tabbar.map)
    }
}
