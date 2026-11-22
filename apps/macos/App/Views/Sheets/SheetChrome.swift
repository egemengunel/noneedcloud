import SwiftUI

/// Sheet layout convention (UX spec §2): title, content, footer with the
/// secondary/reset action on the left and Done on the right.
struct SheetChrome<Content: View, Secondary: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @ViewBuilder let secondary: Secondary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            .padding(22)
            content
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider().padding(.top, 16)
            HStack {
                secondary
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 500)
        .frame(minHeight: 360)
    }
}
