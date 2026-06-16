//
//  TrashCleanerService.swift
//  mac sysdata cleaner
//
//  Created by prabch on 13-06-2026.
//

import Foundation

// Service dedicted to powerfull and accurate Trash clening
final class TrashCleanerService: @unchecked Sendable {
    static let shared = TrashCleanerService()
    
    private init() {}
    
    // Gets all trash dirctories including external volumes
    nonisolated private func getTrashDirectories() -> [URL] {
        let fileManager = FileManager.default
        var trashDirs: [URL] = []
        
        // Main user trash
        let homeTrash = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        trashDirs.append(homeTrash)
        
        // External volumes trash
        let uid = getuid()
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        
        if let volumes = try? fileManager.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for volume in volumes {
                let externalTrash = volume.appendingPathComponent(".Trashes").appendingPathComponent("\(uid)")
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: externalTrash.path, isDirectory: &isDir) && isDir.boolValue {
                    trashDirs.append(externalTrash)
                }
            }
        }
        
        return trashDirs
    }
    
    // Accurately calcultes the total size of an item
    nonisolated private static func calculateItemSizeAccurately(url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                    while let subURL = enumerator.nextObject() as? URL {
                        if let fileSize = try? subURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            totalSize += Int64(fileSize)
                        }
                    }
                }
            } else {
                if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize = Int64(fileSize)
                }
            }
        }
        
        return totalSize
    }
    
    // Gets all indivdual items inside all trash dirctories
    func getTrashItems() async -> [FileItem] {
        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            var items: [FileItem] = []
            let dirs = self.getTrashDirectories()
            
            for dir in dirs {
                if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) {
                    for itemURL in contents {
                        let size = TrashCleanerService.calculateItemSizeAccurately(url: itemURL)
                        items.append(FileItem(name: itemURL.lastPathComponent, url: itemURL, sizeBytes: size))
                    }
                }
            }
            
            items.sort { $0.sizeBytes > $1.sizeBytes }
            return items
        }.value
    }
    
    func calculateTotalSize() async -> Int64 {
        let items = await getTrashItems()
        return items.reduce(0) { $0 + $1.sizeBytes }
    }
    
    // Last resort defense: deletes from child to parent
    nonisolated private static func bottomUpDelete(url: URL) throws {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return
        }
        
        if isDir.boolValue {
            // Delete children first
            if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) {
                for childURL in contents {
                    try? bottomUpDelete(url: childURL) // Ignore individual child errors, try to delete as much as possible
                }
            }
        }
        
        // Then delete the item itself
        try fileManager.removeItem(at: url)
    }
    
    // Force deltes a specific item bypassing limits
    nonisolated static func forceDelete(url: URL) async throws {
        // Unlock flags first
        let unlockProcess = Process()
        unlockProcess.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        unlockProcess.arguments = ["-R", "nouchg", url.path]
        unlockProcess.standardOutput = FileHandle.nullDevice
        unlockProcess.standardError = FileHandle.nullDevice
        try? unlockProcess.run()
        unlockProcess.waitUntilExit()
        
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: url)
        } catch {
            // Fallbak to rm -rf
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/rm")
            process.arguments = ["-rf", url.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            try process.run()
            
            var exited = false
            for _ in 0..<10 {
                if !process.isRunning {
                    exited = true
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            
            if !exited {
                process.terminate()
            }
            
            if !exited || process.terminationStatus != 0 {
                // Try last resort bottom-up deletion
                try? bottomUpDelete(url: url)
                
                if fileManager.fileExists(atPath: url.path) {
                    let errorMessage = !exited ? "Failed to force delete item. It may be strongly locked by the system." : "Failed to force delete item. Insufficient permissions."
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                }
            }
        }
    }
    
    func deleteItem(url: URL, progress: (@Sendable (URL, CleanStatus, Double) -> Void)? = nil) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let size = TrashCleanerService.calculateItemSizeAccurately(url: url)
            progress?(url, .deleting(size: size), 0.5)
            
            do {
                try await TrashCleanerService.forceDelete(url: url)
                progress?(url, .success, 1.0)
            } catch {
                progress?(url, .error(error.localizedDescription), 1.0)
                throw error
            }
        }.value
    }
    
    func cleanAll(progress: (@Sendable (URL, CleanStatus, Double) -> Void)? = nil) async throws {
        let items = await getTrashItems()
        let total = Double(items.count)
        
        var errors: [String] = []
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            
            let progressValue = Double(index) / total
            progress?(item.url, .deleting(size: item.sizeBytes), progressValue)
            
            do {
                try await TrashCleanerService.forceDelete(url: item.url)
                let completeProgress = Double(index + 1) / total
                progress?(item.url, .success, completeProgress)
            } catch {
                let failProgress = Double(index + 1) / total
                errors.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
                progress?(item.url, .error(error.localizedDescription), failProgress)
            }
        }
        
        if !errors.isEmpty {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [NSLocalizedDescriptionKey: "Failed to force delete some items: \(errors.joined(separator: ", "))"])
        }
    }
}
