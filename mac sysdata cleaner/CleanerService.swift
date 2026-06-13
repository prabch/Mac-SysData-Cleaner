//
//  CleanerService.swift
//  mac sysdata cleaner
//
//  Created by prabch on 05-04-2026.
//

import Foundation

// Enum to trak the status of a deleteion operation
public enum CleanStatus: Equatable {
    case deleting(size: Int64?)
    case success
    case error(String)
}

// Singelton service for file operations and manger of deltetions
class CleanerService {
    static let shared = CleanerService()
    
    private init() {}
    
    nonisolated private static func calculateItemSize(path: String) -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8),
               let firstPart = output.split(separator: "\t").first,
               let sizeKB = Int64(firstPart.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return sizeKB * 1024
            }
        } catch {}
        return 0
    }

    // Calcullates the toal size of a dirctory or file asyncronously
    func calculateSize(for url: URL) async -> Int64 {
        return await Task.detached(priority: .background) {
            let isTrash = url.path.hasSuffix(".Trash")
            if isTrash {
                return await TrashCleanerService.shared.calculateTotalSize()
            }
            
            return CleanerService.calculateItemSize(path: url.path)
        }.value
    }
    
    nonisolated private static func forceDelete(url: URL) async throws {
        // Run chflags with timeout
        let unlockProcess = Process()
        unlockProcess.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        unlockProcess.arguments = ["-R", "nouchg", url.path]
        unlockProcess.standardOutput = FileHandle.nullDevice
        unlockProcess.standardError = FileHandle.nullDevice
        try? unlockProcess.run()
        
        for _ in 0..<5 {
            if !unlockProcess.isRunning { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if unlockProcess.isRunning {
            unlockProcess.terminate()
        }
        
        // Run rm with timeout
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/rm")
        process.arguments = ["-rf", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        
        var exited = false
        for _ in 0..<5 {
            if !process.isRunning {
                exited = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        if !exited {
            process.terminate()
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [NSLocalizedDescriptionKey: "Failed to force delete item. It may be locked by the system or iCloud."])
        }
        
        if process.terminationStatus != 0 {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [NSLocalizedDescriptionKey: "Failed to force delete item. It may be locked by the system."])
        }
    }
    

    
    func clean(url: URL, permanently: Bool = false, progress: (@Sendable (URL, CleanStatus, Double) -> Void)? = nil) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let isTrash = url.path.contains(".Trash")
            let shouldDeletePermanently = permanently || isTrash
            
            if url.path.hasSuffix(".Trash") {
                try await TrashCleanerService.shared.cleanAll(progress: progress)
                return
            }
            
            // Safe removal: delete contents rather than the directory itself
            guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
                // If we can't get contents (e.g., it's a file or inaccessible), try removing it directly
                try Task.checkCancellation()
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
                progress?(url, .deleting(size: size), 0.5)
                do {
                    if shouldDeletePermanently {
                        do {
                            try fileManager.removeItem(at: url)
                        } catch {
                            try await CleanerService.forceDelete(url: url)
                        }
                    } else {
                        try fileManager.trashItem(at: url, resultingItemURL: nil)
                    }
                    progress?(url, .success, 1.0)
                } catch {
                    print("Failed to process item at \(url): \(error.localizedDescription)")
                    progress?(url, .error(error.localizedDescription), 1.0)
                    throw error
                }
                return
            }
            
            let total = Double(contents.count)
            for (index, fileURL) in contents.enumerated() {
                try Task.checkCancellation()
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
                let progressValue = Double(index) / total
                progress?(fileURL, .deleting(size: size), progressValue)
                do {
                    if shouldDeletePermanently {
                        do {
                            try fileManager.removeItem(at: fileURL)
                        } catch {
                            try await CleanerService.forceDelete(url: fileURL)
                        }
                    } else {
                        try fileManager.trashItem(at: fileURL, resultingItemURL: nil)
                    }
                    let completeProgress = Double(index + 1) / total
                    progress?(fileURL, .success, completeProgress)
                } catch {
                    print("Failed to process content item at \(fileURL): \(error.localizedDescription)")
                    let failProgress = Double(index + 1) / total
                    progress?(fileURL, .error(error.localizedDescription), failProgress)
                    // We continue even if one file fails
                }
            }
        }.value
    }
    
    func deleteItem(at url: URL, permanently: Bool = false, progress: (@Sendable (URL, CleanStatus, Double) -> Void)? = nil) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let isTrash = url.path.contains(".Trash")
            let shouldDeletePermanently = permanently || isTrash
            
            try Task.checkCancellation()
            
            if fileManager.fileExists(atPath: url.path) {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
                progress?(url, .deleting(size: size), 0.5)
                do {
                    if shouldDeletePermanently {
                        if isTrash {
                            try await TrashCleanerService.shared.deleteItem(url: url, progress: nil)
                        } else {
                            do {
                                try fileManager.removeItem(at: url)
                            } catch {
                                try await CleanerService.forceDelete(url: url)
                            }
                        }
                    } else {
                        try fileManager.trashItem(at: url, resultingItemURL: nil)
                    }
                    progress?(url, .success, 1.0)
                } catch {
                    progress?(url, .error(error.localizedDescription), 1.0)
                    throw error
                }
            }
        }.value
    }
    func getDetails(for url: URL) async -> [FileItem] {
        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            var items: [FileItem] = []
            
            if url.path.hasSuffix(".Trash") {
                return await TrashCleanerService.shared.getTrashItems()
            }
            
            guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: .skipsHiddenFiles) else {
                return items
            }
            
            for fileURL in contents {
                var totalSize: Int64 = 0
                
                if let isDir = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
                    if let enumerator = fileManager.enumerator(at: fileURL, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                        while let subURL = enumerator.nextObject() as? URL {
                            if let fileSize = try? subURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                totalSize += Int64(fileSize)
                            }
                        }
                    }
                } else {
                    if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize = Int64(fileSize)
                    }
                }
                
                if totalSize > 0 {
                    items.append(FileItem(name: fileURL.lastPathComponent, url: fileURL, sizeBytes: totalSize))
                }
            }
            
            items.sort { $0.sizeBytes > $1.sizeBytes }
            return items
        }.value
    }
}
