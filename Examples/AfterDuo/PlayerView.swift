import SwiftUI

struct PlayerView: View {
    var body: some View {
        NavigationStack {
            ArrangementView {
                Text("Video")
            } secondary: {
                List { Text("Controls") }
            }
            .arrangementViewStyle(.split)
            .toolbar {
                Button("Favorite", systemImage: "star") {}
            }
        }
    }
}
