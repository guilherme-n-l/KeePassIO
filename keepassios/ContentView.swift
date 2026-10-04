import SwiftUI

/// Root view. Until databases can be opened it shows the empty library state.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No Databases", systemImage: "lock.rectangle.stack")
            } description: {
                Text("Open a KeePass database (.kdbx) from the Files app to get started.")
            }
            .navigationTitle("KeePassIOS")
        }
    }
}

#Preview {
    ContentView()
}
