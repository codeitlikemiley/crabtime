import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Paragraph 1")
            Text("Paragraph 2")
            Text("Paragraph 3")
        }
        .textSelection(.enabled)
        .padding()
    }
}
