import SwiftUI

struct PlaceholderDestinationView: View {
    let destination: SidebarDestination

    var body: some View {
        ContentUnavailableView(
            "\(destination.title) Comes Next",
            systemImage: destination.systemImage,
            description: Text("This first vertical slice stops after folder selection, one-shot import, and base summary rendering.")
        )
    }
}
