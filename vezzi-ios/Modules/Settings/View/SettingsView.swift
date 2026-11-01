import SwiftUI

struct SettingsView: View {
    var body: some View {
        Color.Background.primary
            .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .navigationTitle(Texts.Tabbar.settings)
    }
}
