import SwiftUI

/// Classic barbershop: cream paper and charcoal ink, brass accents, a barber-pole red and blue,
/// and New York (the system serif) for display type. Colors live in Assets.xcassets with dark variants.
enum Theme {
    static let paper = Color("Paper")
    static let card = Color("Card")
    static let ink = Color("Ink")
    static let muted = Color("Muted")
    static let line = Color("Line")
    static let brass = Color("Brass")
    static let oxblood = Color("Oxblood")
    static let navy = Color("Navy")
    static let buttonFill = Color("Button")
    static let buttonText = Color("ButtonText")

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}

/// Small, widely tracked capitals in brass, like lettering on a shop window.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.brass

    init(_ text: String, color: Color = Theme.brass) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(color)
    }
}

/// A hairline with a diamond in the middle.
struct OrnamentRule: View {
    var width: CGFloat = 140

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().frame(height: 1)
            Image(systemName: "diamond.fill").font(.system(size: 6))
            Rectangle().frame(height: 1)
        }
        .foregroundStyle(Theme.brass)
        .frame(width: width)
        .accessibilityHidden(true)
    }
}

/// Red, cream and blue diagonal stripes, like a barber pole laid on its side.
struct BarberStripe: View {
    var height: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let stripe: CGFloat = 12
            let colors = [Theme.oxblood, Color.white, Theme.navy, Color.white]
            var x: CGFloat = -size.height
            var index = 0
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x + size.height + stripe, y: 0))
                path.addLine(to: CGPoint(x: x + stripe, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(colors[index % colors.count]))
                x += stripe
                index += 1
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Diagonal hatching for breaks on the timeline.
struct Hatching: Shape {
    var spacing: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.serif(.headline, weight: .semibold))
            .foregroundStyle(Theme.buttonText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.buttonFill, in: RoundedRectangle(cornerRadius: 4))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// A label above the field and a hairline below it, in place of the default rounded box.
struct LinedField<Field: View>: View {
    let label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(label, color: Theme.muted)
            field
                .font(.body)
                .foregroundStyle(Theme.ink)
                .tint(Theme.brass)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

/// Error or confirmation text under a form.
struct FormMessage: View {
    let text: String
    var isError = true

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.circle" : "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(isError ? Theme.oxblood : Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
