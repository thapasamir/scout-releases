import Foundation
import SwiftUI

enum SearchMode: Hashable, CaseIterable {
    case literal
    case semantic
    case hybrid

    var friendlyName: String {
        switch self {
        case .literal:  return "Exact"
        case .semantic: return "Smart"
        case .hybrid:   return "Best Match"
        }
    }

    var detail: String {
        switch self {
        case .literal:  return "Finds screenshots containing these exact words"
        case .semantic: return "Understands meaning, even with different words"
        case .hybrid:   return "Combines both for the most complete results"
        }
    }

    var icon: String {
        switch self {
        case .literal:  return "textformat"
        case .semantic: return "sparkles"
        case .hybrid:   return "wand.and.stars"
        }
    }

    var tint: Color {
        switch self {
        case .literal:  return .blue
        case .semantic: return .purple
        case .hybrid:   return .orange
        }
    }
}


struct SearchQuery {
    let text: String
    let mode: SearchMode

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

struct SearchResult: Identifiable {
    let id: Int64
    let filePath: String
    let fileName: String
    let fileCreatedAt: Double
    let ocrText: String?
    let thumbnailPath: String?
    let sourceApp: String?
    var relevanceScore: Double

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var createdDate: Date { Date(timeIntervalSince1970: fileCreatedAt) }
}
