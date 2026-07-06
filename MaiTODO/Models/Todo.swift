import Foundation

struct Todo: Codable, Identifiable {
    let id: Int
    let setId: Int?
    let content: String
    let done: Bool
}
