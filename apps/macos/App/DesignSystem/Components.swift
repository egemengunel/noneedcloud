import SwiftUI

// MARK: - Buttons (Düğme / Birincil · İkincil · Nötr · Dikkat · Durdur)

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, neutral, attention, stop }

    var kind: Kind = .primary
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 15 : 14, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 22)
            .frame(minHeight: large ? 52 : 44)
            .background(background, in: Capsule())
            .overlay {
                if kind == .secondary || kind == .stop {
                    Capsule().strokeBorder(Theme.line)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary, .neutral: Theme.ink
        case .attention: Theme.amber
        case .stop: Theme.red
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.blue
        case .secondary, .stop: Theme.card
        case .neutral: Theme.gray
        case .attention: Theme.amberTint
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pillPrimary: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var pillStop: PillButtonStyle { PillButtonStyle(kind: .stop) }
}

// MARK: - Metric tile (Gösterge / Ölçüm)

struct MetricTile: View {
    let value: String
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: value)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 5)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)
        }
        .lineLimit(1)
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Grouped list (Grup Liste / Satır)

/// A white rounded card holding rows separated by inset dividers.
struct GroupList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    row
                    if index < rows.count - 1 {
                        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 67).padding(.trailing, 17)
                    }
                }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.lightLine))
    }
}

struct GroupListRow<Trailing: View>: View {
    let systemImage: String
    var iconColor: Color = Theme.blue
    let title: String
    let subtitle: String
    var showsChevron = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let row = HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 42, height: 42)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            trailing
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 17)
        .frame(minHeight: 62)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }
}

extension GroupListRow where Trailing == EmptyView {
    init(
        systemImage: String,
        iconColor: Color = Theme.blue,
        title: String,
        subtitle: String,
        showsChevron: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            systemImage: systemImage, iconColor: iconColor, title: title, subtitle: subtitle,
            showsChevron: showsChevron, action: action, trailing: { EmptyView() }
        )
    }
}

// MARK: - Small pieces

/// Rounded-square icon badge (Simge rozeti).
struct IconBadge: View {
    let systemImage: String
    var color: Color = Theme.blue
    var background: Color = Theme.blueTint

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Pill-shaped status label ("Yedek güncel", "Yazma erişimi var").
struct StatusPill: View {
    let text: String
    var color: Color = Theme.green
    var background: Color = Theme.mint

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(background, in: Capsule())
    }
}

struct SectionTitle: View {
    let text: LocalizedStringKey
    var size: CGFloat = 18

    init(_ text: LocalizedStringKey, size: CGFloat = 18) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Theme.ink)
    }
}

/// A light grey info card (surface background, light border).
struct SurfaceCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.lightLine))
    }
}

/// Vertical stepper used by setup and the live-backup stages.
struct StepperList: View {
    struct Item: Identifiable {
        enum State { case done, current, upcoming }
        var id: Int
        var title: String
        var subtitle: String
        var state: State
    }

    let items: [Item]
    var spacing: CGFloat = 14
    var markerSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 13) {
                    marker(item)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: markerSize >= 30 ? 15 : 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(item.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .background(alignment: .topLeading) {
            Rectangle()
                .fill(Theme.line)
                .frame(width: 2)
                .padding(.vertical, markerSize / 2)
                .padding(.leading, markerSize / 2 - 1)
        }
    }

    @ViewBuilder
    private func marker(_ item: Item) -> some View {
        ZStack {
            switch item.state {
            case .done:
                Circle().fill(Theme.mint)
                Image(systemName: "checkmark")
                    .font(.system(size: markerSize * 0.45, weight: .bold))
                    .foregroundStyle(Theme.green)
            case .current:
                Circle().fill(Theme.blue)
                Text("\(item.id)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            case .upcoming:
                Circle().fill(Theme.card)
                Circle().strokeBorder(Theme.line)
                Text("\(item.id)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: markerSize, height: markerSize)
    }
}

/// Bottom bar with a divider, used by setup, live backup and attention screens.
struct WindowFooter<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                leading
                Spacer()
                trailing
            }
            .padding(.vertical, 18)
        }
    }
}
