import SwiftUI

struct SearchView: View {
    var body: some View {
        Color.Background.primary
            .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        SearchView()
            .navigationTitle(Texts.Tabbar.search)
    }
}
