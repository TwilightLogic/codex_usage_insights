import SwiftUI

struct PlaceholderDestinationView: View {
    let destination: SidebarDestination

    var body: some View {
        ContentUnavailableView(
            "\(destination.title) Is Still In Progress",
            systemImage: destination.systemImage,
            description: Text("This destination has not been implemented yet for the current MVP slice.")
        )
    }
}
