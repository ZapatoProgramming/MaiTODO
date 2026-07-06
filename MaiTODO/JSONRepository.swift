import Foundation

final class JSONRepository {
    private static let appFolderName = "MaiTODO"

    private static func fileURL(filename: String) throws -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        let folderURL = applicationSupportURL.appendingPathComponent(
            appFolderName,
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )

        return folderURL.appendingPathComponent(filename)
    }

    static func read<T: Codable>(_ type: T.Type, from filename: String) throws -> [T] {
        let url = try fileURL(filename: filename)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([T].self, from: data)
    }

    static func write<T: Codable>(_ items: [T], to filename: String) throws {
        let url = try fileURL(filename: filename)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(items)
        try data.write(to: url, options: [.atomic])
    }
}
