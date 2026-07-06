import Foundation

struct Set: Codable, Identifiable {
    let id: Int
    let color: String?
    let subsetId: Int?
    let name: String
}
