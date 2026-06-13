//
//  CleanerModel.swift
//  mac sysdata cleaner
//
//  Created by prabch on 15-03-2026.
//

import Foundation

// Represents a specific area in the system that can be clened
struct CleanableArea: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let detailedInfo: String
    let path: URL
    
    // The curent state of the area (e.g. loading, redy, clened)
    var state: CleanState = .loading
    var sizeBytes: Int64 = 0
    let iconName: String
    
    // Flags to indicate risk levls during deletin
    var isHighRisk: Bool = false
    var isExtremelyHighRisk: Bool = false
    var defaultOrder: Int = 0
    
    // Convience propery to format size
    var formattedSize: String {
        if sizeBytes == 0 { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}

// Defines possibe stats for an area
enum CleanState: Equatable {
    case loading
    case ready
    case cleaning
    case cleaned
    case failed(String)
    
    // Indicates if the state allows for clening
    var canClean: Bool {
        switch self {
        case .ready, .failed: return true
        default: return false
        }
    }
}

// Represnts an idividual file or folder that can be deleted
struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let sizeBytes: Int64
    var isDeleting: Bool = false
    
    var formattedSize: String {
        if sizeBytes == 0 { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}

// Log item to trak the progess of cleaning operations
struct CleanLogItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let sizeBytes: Int64?
    var status: CleanStatus
}

// Sorting options for the UI list
enum SortOption: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case size = "Size"
    case title = "Title"
    case hideEmpty = "Hide Empty"

    var id: String { self.rawValue }
}
