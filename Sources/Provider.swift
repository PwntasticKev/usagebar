import SwiftUI

enum Provider: String, CaseIterable, Hashable {
    case claude, codex

    var name: String { self == .claude ? "Claude" : "Codex" }
    var symbol: String { self == .claude ? "asterisk" : "chevron.left.forwardslash.chevron.right" }
    var tint: Color { self == .claude ? Palette.claude : Palette.codex }
}

struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = Layout.iconSize

    var body: some View {
        Image(systemName: provider.symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(provider.tint)
            .frame(width: size + 3)
    }
}
