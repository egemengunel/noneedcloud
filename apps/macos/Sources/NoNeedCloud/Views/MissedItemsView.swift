import SwiftUI

struct MissedItemsView: View {
    let items: [BackupFileError]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("Nothing missed in the last run.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("These items could not be copied and will be retried automatically next run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    BackupFileErrorRow(error: item)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
