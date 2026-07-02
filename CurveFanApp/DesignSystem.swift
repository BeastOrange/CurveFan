import SwiftUI

// MARK: - Design Tokens

enum DesignTokens {
    enum Spacing {
        static let tight: CGFloat = 4
        static let compact: CGFloat = 8
        static let card: CGFloat = 6
        static let section: CGFloat = 18
        static let page: CGFloat = 24
        static let menuBarHeaderH: CGFloat = 16
        static let menuBarHeaderV: CGFloat = 10
    }

    enum Radius {
        static let small: CGFloat = 7
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
    }

    enum Opacity {
        static let disabledFill: Double = 0.07
        static let cardBorder: Double = 0.09
        static let chartGridLine: Double = 0.12
        static let alertTint: Double = 0.13
        static let chartAreaFill: Double = 0.14
        static let inactivePill: Double = 0.16
        static let chartBorder: Double = 0.18
        static let disabledBar: Double = 0.35
        static let emptyChartLine: Double = 0.55
        static let activeBar: Double = 0.75
        static let activeAvatar: Double = 0.85
        static let chartDotStroke: Double = 0.9
    }

    enum Typography {
        static let statusIcon: CGFloat = 8
        static let caption: CGFloat = 10
        static let alertMessage: CGFloat = 11
        static let footerLabel: CGFloat = 12
        static let metricValue: CGFloat = 13
        static var largeRPM: Font { .system(size: 42, weight: .bold, design: .rounded) }
    }
}

// MARK: - CardView

/// Drop-in replacement for `GroupBox { VStack { ... }.padding(6) } label: { Label(...) }`.
struct CardView<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    init(title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        GroupBox {
            content()
                .padding(DesignTokens.Spacing.card)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

// MARK: - FormCard

/// Drop-in replacement for `GroupBox { Form { ... }.formStyle(.grouped).scrollContentBackground(.hidden) } label: { Label(...) }`.
struct FormCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    init(title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        GroupBox {
            Form {
                content()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}