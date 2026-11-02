import SwiftUI

struct ShoppingListView: View {
    var body: some View {
        Color.Background.primary
            .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        ShoppingListView()
            .navigationTitle(Texts.Tabbar.shoppingList)
    }
}
