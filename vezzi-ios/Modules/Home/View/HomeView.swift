import SwiftUI

struct HomeView: View {
    var body: some View {
        Color.Background.primary
            .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .navigationTitle(Texts.Tabbar.home)
    }
}
