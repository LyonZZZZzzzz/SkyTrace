import SkyTraceCore
import SkyTraceUI
import SwiftUI

struct DetailsSheet: View {
    let object: CelestialObject
    let position: SkyPosition?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ObjectDetailsContent(object: object, position: position)
                    .padding(20)
            }
            .navigationTitle("天体详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
