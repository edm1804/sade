import Foundation

struct VoiceNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var file: String
    var created = Date()
}
struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var notes = ""
    var category = "Genel"
    var priority = "Normal"
    var done = false
    var completedAt: Date?
    var created = Date()
    var scheduledDay: Date?
    var reminder: Date?
    var timerEnd: Date?
    var voices: [VoiceNote] = []
    var subtasks: [Subtask] = []

    var plannerDay: Date { scheduledDay ?? reminder ?? timerEnd ?? created }
}
struct Subtask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var done = false
}
struct SavedData: Codable { var tasks: [TaskItem]; var categories: [String] }

enum SadeData {
    static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Sade", isDirectory: true)
}

enum SadeTaskLink {
    static let scheme = "sade-task"

    static func url(for id: UUID) -> URL {
        URL(string: "\(scheme)://open/\(id.uuidString)")!
    }

    static func taskID(from url: URL) -> UUID? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == scheme, parts.host == "open",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil, parts.path.first == "/" else { return nil }
        return UUID(uuidString: String(parts.path.dropFirst()))
    }
}
