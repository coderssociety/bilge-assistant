import AsistanCore
import Foundation

/// Meeting notes go to ~/Documents/Bilge/Toplantılar, one Markdown file per meeting named by its date and time,
/// readable only by the user.
enum MeetingNotesFile {
    static func folder() throws -> URL {
        let folder = URL.documentsDirectory
            .appending(path: AppIdentity.name, directoryHint: .isDirectory)
            .appending(path: "Toplantılar", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A second meeting in the same minute gets "(2)" rather than replacing the first.
    static func write(_ notes: MeetingNotes, date: Date) throws -> URL {
        let folder = try folder()
        let base = MeetingNotes.fileName(for: date)
        var url = folder.appending(path: "\(base).md")
        var copy = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(base) (\(copy)).md")
            copy += 1
        }
        try PrivateFile.write(Data(notes.markdown.utf8), to: url)
        return url
    }
}
