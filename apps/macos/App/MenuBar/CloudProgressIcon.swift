import AppKit

/// The menu bar icon: the brand cloud outline whose inside fills from the
/// bottom as a backup progresses (0…1), plus an "!" badge when something
/// needs attention. Template image, so it follows the menu bar's appearance.
@MainActor
enum CloudProgressIcon {
    /// Brand cloud ("Marka / Bulut") path from the Figma vector, in a
    /// 95.4 × 66 box. First subpath = outer outline, second = the hole.
    private static let pathData = """
    M39.7544 0.73109C53.591 -2.19745 65.3674 3.82145 71.95 16.1084C90.0997 13.8587 101.779 33.4833 91.6629 47.887C89.56 50.8886 86.6901 53.2697 83.3526 54.7812C79.5359 56.5015 73.0875 57.363 68.7137 58.1366L52.1458 61.0541L34.5298 64.2069C30.7232 64.8852 24.9791 66.1319 21.3591 65.9818C17.8376 65.8108 14.4033 64.8122 11.3401 63.0669C6.10995 60.1128 2.29504 55.1732 0.758008 49.3678C-0.769176 43.7073 0.0314389 37.6716 2.97759 32.6039C6.57809 26.375 11.5386 23.4031 18.2747 21.6179C21.1245 10.5517 29.056 3.76707 39.7544 0.73109ZM50.6126 51.4234L68.2286 48.2855C70.8932 47.8147 76.6941 46.9503 78.9574 45.9862C80.7345 45.236 82.2567 43.9911 83.3459 42.3992C84.9557 40.0322 85.5471 37.117 84.984 34.3104C84.4677 31.531 82.8586 29.0747 80.5158 27.4931C75.612 24.2355 70.3671 26.1896 65.5582 28.4024C64.234 21.9772 62.148 16.7564 56.3931 12.9806C52.177 10.1628 46.9984 9.1796 42.0444 10.2577C41.7918 10.3109 41.5396 10.3658 41.2903 10.4221C32.1656 13.2329 26.4539 21.7187 27.506 31.2511C22.7388 30.7881 18.4722 30.67 14.5162 33.9318C11.9774 36.0372 10.3857 39.0712 10.098 42.3565C9.79967 45.7446 10.9047 49.3675 13.1217 51.9593C15.2221 54.3792 18.187 55.8795 21.3809 56.1377C24.596 56.3837 31.2145 54.927 34.6831 54.2919C39.9864 53.3091 45.2972 52.3528 50.6126 51.4234Z
    """
    private static let box = CGSize(width: 95.4042, height: 65.9943)

    /// Ring (outline with hole) and solid outer shape, in SVG coordinates.
    private static let (ring, solid): (CGPath, CGPath) = {
        let subpaths = parse(pathData)
        let ring = CGMutablePath()
        subpaths.forEach { ring.addPath($0) }
        return (ring, subpaths.first ?? ring)
    }()

    /// Icon height in the menu bar, in points.
    static let size = NSSize(width: 21, height: 21 * box.height / box.width + 0.5)

    /// `fraction` nil = idle outline; 0…1 = fill level while backing up.
    static func image(fraction: Double?, attention: Bool) -> NSImage {
        let badgeWidth: CGFloat = attention ? 6 : 0
        let canvas = NSSize(width: size.width + badgeWidth, height: size.height)
        let image = NSImage(size: canvas, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = size.width / box.width
            context.saveGState()
            // SVG is y-down; flip into the image's y-up space.
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: scale, y: -scale)
            context.setFillColor(NSColor.black.cgColor)

            context.addPath(ring)
            context.fillPath(using: .evenOdd)

            if let fraction, fraction > 0 {
                // Fill the inside from the bottom (SVG y = box.height) up.
                let level = box.height * (1 - min(1, fraction))
                context.saveGState()
                context.clip(to: CGRect(x: 0, y: level, width: box.width, height: box.height - level))
                context.addPath(solid)
                context.fillPath()
                context.restoreGState()
            }
            context.restoreGState()

            if attention {
                let bang = NSAttributedString(string: "!", attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .heavy),
                    .foregroundColor: NSColor.black,
                ])
                bang.draw(at: NSPoint(x: size.width + 1, y: (size.height - 14) / 2))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "NoNeedCloud"
        return image
    }

    // MARK: Minimal SVG path parser (absolute M, L, C, Z — all this path uses)

    private static func parse(_ data: String) -> [CGPath] {
        var tokens: [String] = []
        var number = ""
        func flush() { if !number.isEmpty { tokens.append(number); number = "" } }
        for char in data {
            if "MLCZ".contains(char) {
                flush(); tokens.append(String(char))
            } else if char == " " || char == "," || char == "\n" {
                flush()
            } else if char == "-", !number.isEmpty, number.last != "e" {
                flush(); number.append(char)
            } else {
                number.append(char)
            }
        }
        flush()

        var paths: [CGPath] = []
        var current = CGMutablePath()
        var index = 0
        var command = ""
        func value() -> CGFloat { defer { index += 1 }; return CGFloat(Double(tokens[index]) ?? 0) }
        while index < tokens.count {
            if ["M", "L", "C", "Z"].contains(tokens[index]) {
                command = tokens[index]
                index += 1
                if command == "Z" {
                    current.closeSubpath()
                    paths.append(current)
                    current = CGMutablePath()
                    continue
                }
            }
            switch command {
            case "M": current.move(to: CGPoint(x: value(), y: value()))
            case "L": current.addLine(to: CGPoint(x: value(), y: value()))
            case "C":
                let c1 = CGPoint(x: value(), y: value())
                let c2 = CGPoint(x: value(), y: value())
                current.addCurve(to: CGPoint(x: value(), y: value()), control1: c1, control2: c2)
            default: index += 1
            }
        }
        return paths
    }
}
