import SwiftUI

/// Loading screen shown at every launch while the app checks the
/// destination and Photos access. Same navy/light-blue brand field as the
/// welcome screen, with the cloud centred.
struct LaunchView: View {
    @State private var appeared = false
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Theme.navy

            CoverRings(scale: 0.62)
                .scaleEffect(pulsing ? 1.02 : 0.98)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.9)
                .offset(y: -40)

            VStack(spacing: 14) {
                Spacer()
                Wordmark(color: .white, height: 34)
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.lightBlue)
                    Text("Checking your backup…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.lightBlue)
                }
            }
            .padding(.bottom, 70)
            .opacity(appeared ? 1 : 0)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.3)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulsing = true }
        }
        .accessibilityElement(children: .combine)
    }
}
