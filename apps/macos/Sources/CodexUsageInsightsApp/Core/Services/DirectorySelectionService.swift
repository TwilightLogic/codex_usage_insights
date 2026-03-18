import AppKit
import Foundation

protocol DirectoryPicking: Sendable {
    @MainActor
    func pickDirectory() -> URL?
}

struct AppKitDirectoryPicker: DirectoryPicking {
    @MainActor
    func pickDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Codex Logs Folder"
        panel.message = "Select the local folder that contains Codex session JSONL logs."
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/sessions", isDirectory: true)

        return panel.runModal() == .OK ? panel.url : nil
    }
}
