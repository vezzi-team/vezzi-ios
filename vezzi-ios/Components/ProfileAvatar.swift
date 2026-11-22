import SwiftUI

struct ProfileAvatar: View {
    let email: String
    var isCompact = false

    var body: some View {
        Text(verbatim: String(email.prefix(1)).uppercased())
            .font((isCompact ? Font.headline : .title3).weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Color.Mascot.ink)
            .frame(width: diameter, height: diameter)
            .background(Color.accentColor, in: .circle)
            .accessibilityHidden(true)
    }

    private var diameter: CGFloat { isCompact ? 36 : 52 }
}
