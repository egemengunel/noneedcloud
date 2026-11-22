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

            ZStack {
                Circle()
                    .fill(Color(hex: 0x1D2B47))
                    .frame(width: 420, height: 420)
                    .scaleEffect(pulsing ? 1.04 : 0.96)
                Circle()
                    .fill(Color(hex: 0x223258))
                    .frame(width: 300, height: 300)
                    .scaleEffect(pulsing ? 0.97 : 1.03)
                BrandCloud(color: Theme.lightBlue, width: 170)
                    .offset(y: appeared ? 0 : 10)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.9)
            .offset(y: -40)

            VStack(spacing: 14) {
                Spacer()
                Text(verbatim: "NoNeedCloud")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(.white)
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
