import Foundation

struct Set: Codable, Identifiable {
    let id: Int
    let color: String?
    let subsetId: Int?
    let name: String
    let order: Double

    init(id: Int, color: String?, subsetId: Int?, name: String, order: Double) {
        self.id = id
        self.color = color
        self.subsetId = subsetId
        self.name = name
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        subsetId = try container.decodeIfPresent(Int.self, forKey: .subsetId)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decodeIfPresent(Double.self, forKey: .order) ?? -1
    }
}
