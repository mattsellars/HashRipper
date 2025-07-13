//
//  FirmwareReleaseInfo.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation

struct FirmwareReleaseInfo: Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case changeLog = "html_url"
        case draft
        case prerelease
        case body // markdown
        case name
        case tag = "tag_name"
        case assets
        case url
    }

    enum DateCodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case publishedAt = "published_at"
    }

    let url: String

    var id: String { url }

    var changeLog: String
    var draft: Bool
    var prerelease: Bool
    var publishedAt: Date
    var body: String
    var name: String
    var tag: String
    var assets: [ReleaseAsset]

    init(from decoder: any Decoder) throws {
        let jsonDateDecoder = JSONDecoder()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dateContainer = try decoder.container(keyedBy: DateCodingKeys.self)

        self.url = try container.decode(String.self, forKey: .url)
        self.name = try container.decode(String.self, forKey: .name)
        self.tag = try container.decode(String.self, forKey: .tag)
        self.changeLog = try container.decode(String.self, forKey: .changeLog)
        self.draft = try container.decode(Bool.self, forKey: .draft)
        self.prerelease = try container.decode(Bool.self, forKey: .prerelease)
        self.publishedAt = try dateContainer.decode(Date.self, forKey: .publishedAt)
        self.body = try container.decode(String.self, forKey: .body)
        self.assets = try container.decode([ReleaseAsset].self, forKey: .assets)
    }
}

struct ReleaseAsset: Codable, Hashable {
    enum CodingKeys: String, CodingKey {
        case name
        case size
        case url
        case browserDownloadUrl = "browser_download_url"
    }
    var name: String
    var size: Int
    var url: String
    var browserDownloadUrl: String
}
