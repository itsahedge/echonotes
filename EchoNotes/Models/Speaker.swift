import SwiftUI

/// Speaker labels for diarized transcripts.
enum Speaker: String, Codable, Sendable {
    case user = "You"
    case remote = "Them"

    /// Display color for speaker labels in the UI.
    var color: Color {
        switch self {
        case .user: .blue
        case .remote: .green
        }
    }

    /// SF Symbol for speaker legend.
    var icon: String {
        switch self {
        case .user: "person.fill"
        case .remote: "person.2.fill"
        }
    }
}
