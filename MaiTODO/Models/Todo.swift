import Foundation

struct Todo: Codable, Identifiable {
    let id: Int
    let setId: Int?
    let content: String
    let done: Bool
    let order: Double

    init(id: Int, setId: Int?, content: String, done: Bool, order: Double) {
        self.id = id
        self.setId = setId
        self.content = content
        self.done = done
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        setId = try container.decodeIfPresent(Int.self, forKey: .setId)
        content = try container.decode(String.self, forKey: .content)
        done = try container.decode(Bool.self, forKey: .done)
        order = try container.decodeIfPresent(Double.self, forKey: .order) ?? -1
    }
}
