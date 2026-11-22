import NoNeedCloudCore
import SwiftUI

/// First-launch screen in the brand style of the Figma cover
/// ("NoNeedCloud · Başlangıç ve senaryolar"): navy field, light-blue cloud.
struct WelcomeView: View {
    /// Returning users see "Continue" instead of "Get Started".
    var isReturning = false
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Theme.navy

                // Cover rings with the cloud on their centre, partly off the
                // trailing edge like the Figma cover (cloud centre 170 pt from it).
                CoverRings(scale: 0.95, cloudOffsetY: appeared ? 0 : 14)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.94)
                    .position(x: proxy.size.width - 170, y: proxy.size.height * 0.5)

                VStack(alignment: .leading, spacing: 0) {
                    Text("WELCOME")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.lightBlue.opacity(0.85))
                    Text(verbatim: "NoNeedCloud")
                        .font(.system(size: 64, weight: .bold))
                        .tracking(-2.4)
                        .foregroundStyle(.white)
                        .padding(.top, 10)
                    Text("Back up iCloud Photos and files to storage you own.")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 18) {
                        WelcomePoint(
                            systemImage: "arrow.triangle.2.circlepath",
                            title: "iCloud syncs. It doesn't back up.",
                            detail: "Delete a photo on one device and it's gone from all of them."
                        )
                        WelcomePoint(
                            systemImage: "externaldrive",
                            title: "Plain files on a drive you own",
                            detail: "An external disk or a NAS. Open your backup in Finder any time."
                        )
                        WelcomePoint(
                            systemImage: "lock.shield",
                            title: "Nothing in iCloud is ever changed",
                            detail: "NoNeedCloud only reads. Everything happens on this Mac."
                        )
                    }
                    .padding(.top, 38)

                    Button(isReturning ? "Continue" : "Get Started", action: onContinue)
                        .buttonStyle(PillButtonStyle(kind: .primary, large: true))
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, 40)
                }
                .frame(maxWidth: 470, alignment: .leading)
                .padding(.leading, 56)
                .offset(y: appeared ? 0 : 12)
                .opacity(appeared ? 1 : 0)
            }
        }
        .clipped()
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.25)) { appeared = true }
        }
    }
}

private struct WelcomePoint: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(Theme.navy2)
                RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.navyLine)
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.lightBlue)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.lightBlue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
