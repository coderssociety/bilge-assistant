import AsistanCore
import Foundation

/// Reads the list of notes and adds text to one, through AppleScript.
enum NotesLibrary {
    static func index() async throws -> [NoteIndex.Entry] {
        let separator = "linefeed & (character id 30) & linefeed"
        let output = try await AppleScriptRunner.run("""
        tell application "Notes"
        set noteIDs to id of notes
        set noteNames to name of notes
        set changeDates to modification date of notes
        end tell
        set currentTime to current date
        set ages to {}
        repeat with changed in changeDates
        set end of ages to ((currentTime - (contents of changed)) as integer)
        end repeat
        set AppleScript's text item delimiters to linefeed
        return (noteIDs as text) & \(separator) & (noteNames as text) & \(separator) & (ages as text)
        """)
        return NoteIndex.parse(output)
    }

    enum AppendOutcome: String {
        case appended, locked, hasAttachments
    }

    /// Notes stores HTML, and rewriting the body of a note with attachments can drop them, so such notes
    /// and locked ones are left alone.
    static func append(_ text: String, toNoteWithID id: String) async throws -> AppendOutcome? {
        let result = try await AppleScriptRunner.run("""
        tell application "Notes"
        set chosenNote to note id \(AppleScriptRunner.quoted(id))
        if password protected of chosenNote then return "\(AppendOutcome.locked.rawValue)"
        if (count of attachments of chosenNote) > 0 then return "\(AppendOutcome.hasAttachments.rawValue)"
        set body of chosenNote to (body of chosenNote) & \(AppleScriptRunner.quoted("<div>\(NoteHTML.escape(text))</div>"))
        return "\(AppendOutcome.appended.rawValue)"
        end tell
        """)
        return AppendOutcome(rawValue: result.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum NoteHTML {
    /// Escapes text so Notes shows it literally.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
