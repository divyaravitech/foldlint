import SwiftUI

struct PlayerView: View {
    var body: some View {
        List {
            ArrangementView {
                NavigationStack { Text("Video") }
            } secondary: {
                Text("Controls")
            }
        }
        .toolbar {
            Button("Favorite") {}
        }
    }
}
