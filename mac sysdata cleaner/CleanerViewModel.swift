//
//  CleanerViewModel.swift
//  mac sysdata cleaner
//
//  Created by prabch on 20-04-2026.
//

import Foundation
import SwiftUI
import Combine

// Main view model manging the state of the cleaner application
@MainActor
class CleanerViewModel: ObservableObject {
    @Published var areas: [CleanableArea] = []
    @Published var isCleaningAll = false
    @Published var freeDiskSpace: String = "Calculating..."
    @Published var sortOption: SortOption = .default {
        didSet {
            sortAreas()
        }
    }
    
    @Published var isShowingCleanOverlay: Bool = false
    @Published var selectedAreaForDetails: CleanableArea? = nil
    @Published var detailsItems: [FileItem]? = nil
    @Published var isCleanFinished: Bool = false
    @Published var cleanLogs: [CleanLogItem] = []
    @Published var currentCleanProgress: Double = 0.0
    @Published var estimatedTimeRemaining: TimeInterval? = nil
    private var cleanStartTime: Date? = nil
    private var activeCleanTask: Task<Void, Never>? = nil
    
    var isAnyLoading: Bool {
        areas.contains { $0.state == .loading }
    }
    
    var totalFreedBytes: Int64 {
        cleanLogs.filter {
            if case .success = $0.status { return true }
            return false
        }.compactMap { $0.sizeBytes }.reduce(0, +)
    }
    
    var totalCleanableSize: Int64 {
        areas.filter { $0.state.canClean }.reduce(0) { $0 + $1.sizeBytes }
    }
    
    var formattedTotalSize: String {
        if totalCleanableSize == 0 { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalCleanableSize)
    }
    
    var hasActionableAreas: Bool {
        areas.contains { $0.state.canClean && $0.sizeBytes > 0 }
    }
    
    private let service = CleanerService.shared
    
    init() {
        setupAreas()
        calculateAllSizes()
        fetchFreeDiskSpace()
    }
    
    // Perfoms initializtion of all cleanable areas
    private func setupAreas() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let rootDirectory = URL(fileURLWithPath: "/")
        
        // General User Targets
        let cachesPath = homeDirectory.appendingPathComponent("Library/Caches")
        let logsPath = homeDirectory.appendingPathComponent("Library/Logs")
        let trashPath = homeDirectory.appendingPathComponent(".Trash")
        let iosBackupsPath = homeDirectory.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        let mailDownloadsPath = homeDirectory.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        let messageAttachmentsPath = homeDirectory.appendingPathComponent("Library/Messages/Attachments")
        
        // Developer Targets
        let derivedDataPath = homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let archivesPath = homeDirectory.appendingPathComponent("Library/Developer/Xcode/Archives")
        let iosDeviceSupportPath = homeDirectory.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport")
        let xcodeSimulatorsPath = homeDirectory.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        let androidEmulatorsPath = homeDirectory.appendingPathComponent(".android/avd")
        let npmCachePath = homeDirectory.appendingPathComponent(".npm")
        let gradleCachePath = homeDirectory.appendingPathComponent(".gradle/caches")
        let cocoaPodsCachePath = homeDirectory.appendingPathComponent("Library/Caches/CocoaPods")
        let yarnCachePath = homeDirectory.appendingPathComponent("Library/Caches/Yarn")

        // Deep System / High Risk Targets
        let appContainersPath = homeDirectory.appendingPathComponent("Library/Containers")
        let groupContainersPath = homeDirectory.appendingPathComponent("Library/Group Containers")
        let applicationSupportPath = homeDirectory.appendingPathComponent("Library/Application Support")
        let systemCachesPath = rootDirectory.appendingPathComponent("Library/Caches")
        let systemLogsPath = rootDirectory.appendingPathComponent("Library/Logs")
        let varLogPath = rootDirectory.appendingPathComponent("var/log")
        let varFoldersPath = rootDirectory.appendingPathComponent("var/folders")
        
        self.areas = [
            // General
            CleanableArea(name: "Application Caches", description: "Temporary files created by apps. Safe to delete, but apps may recreate them later.", detailedInfo: "Deleting these will free up space. Apps will automatically regenerate caches as needed. You won't lose personal data, but some apps might take slightly longer to load the first time after cleaning.", path: cachesPath, iconName: "shippingbox", isHighRisk: false),
            CleanableArea(name: "System & App Logs", description: "Log files used for debugging and diagnostics.", detailedInfo: "Logs are only useful if you are actively troubleshooting a crash or bug. Deleting them is completely safe and frees up space without affecting system performance.", path: logsPath, iconName: "doc.text.magnifyingglass", isHighRisk: false),
            CleanableArea(name: "Trash", description: "Files you have moved to the Trash.", detailedInfo: "This will permanently delete all items currently in your Trash. Make sure you don't need any of these files before cleaning.", path: trashPath, iconName: "trash", isHighRisk: false),
            CleanableArea(name: "iOS Backups", description: "Local backups of your iPhone or iPad.", detailedInfo: "Deleting this will remove your local iOS device backups. You will need to back up your device again or use iCloud backups to restore in the future.", path: iosBackupsPath, iconName: "iphone", isHighRisk: false),
            CleanableArea(name: "Mail Downloads", description: "Attachments downloaded by the Mail app.", detailedInfo: "These are local copies of email attachments. Deleting them is safe; they remain on your email server and will be re-downloaded if you open the email again.", path: mailDownloadsPath, iconName: "envelope", isHighRisk: false),
            CleanableArea(name: "Message Attachments", description: "Photos and files received via iMessage.", detailedInfo: "Deleting this removes locally cached photos and videos from your Messages app. Depending on your iCloud settings, they may be re-downloaded or permanently lost. Proceed with caution.", path: messageAttachmentsPath, iconName: "message", isHighRisk: false),
            
            // Developer
            CleanableArea(name: "Xcode Derived Data", description: "Intermediate build results and indexes generated by Xcode.", detailedInfo: "Deleting Derived Data is a common troubleshooting step for Xcode. The next time you build a project, Xcode will recreate it, though the first build will take longer.", path: derivedDataPath, iconName: "hammer", isHighRisk: false),
            CleanableArea(name: "Xcode Archives", description: "Archived app builds for distribution.", detailedInfo: "These are old builds of your apps meant for App Store submission or ad-hoc distribution. If you don't need to re-upload these specific builds, it is safe to delete them.", path: archivesPath, iconName: "archivebox", isHighRisk: false),
            CleanableArea(name: "iOS Device Support", description: "Files used to debug apps on iOS devices.", detailedInfo: "These files are created when you connect a new iOS device to your Mac for debugging. If you delete them, Xcode will simply extract them again the next time you connect that device. It does not delete your simulators.", path: iosDeviceSupportPath, iconName: "iphone.badge.play", isHighRisk: false),
            CleanableArea(name: "Xcode Simulators", description: "Virtual devices used for testing iOS apps.", detailedInfo: "Deleting these will remove all simulator data, including installed apps and settings. Xcode will prompt you to recreate simulators when you next need them.", path: xcodeSimulatorsPath, iconName: "apps.iphone", isHighRisk: true),
            CleanableArea(name: "Android Emulators", description: "Virtual devices used for testing Android apps.", detailedInfo: "Deleting these removes your configured Android Virtual Devices (AVDs). You will need to recreate them in Android Studio.", path: androidEmulatorsPath, iconName: "candybarphone", isHighRisk: true),
            CleanableArea(name: "NPM Cache", description: "Cached Node.js packages.", detailedInfo: "Safe to delete. NPM will re-download packages as needed for your projects.", path: npmCachePath, iconName: "shippingbox.circle", isHighRisk: false),
            CleanableArea(name: "Gradle Caches", description: "Cached dependencies and build outputs for Gradle.", detailedInfo: "Safe to delete. The next build of a Gradle project will take longer as it re-downloads dependencies.", path: gradleCachePath, iconName: "cup.and.saucer", isHighRisk: false),
            CleanableArea(name: "CocoaPods Cache", description: "Cached CocoaPods dependencies.", detailedInfo: "Safe to delete. CocoaPods will re-download them as needed.", path: cocoaPodsCachePath, iconName: "leaf", isHighRisk: false),
            CleanableArea(name: "Yarn Cache", description: "Cached Yarn packages.", detailedInfo: "Safe to delete. Yarn will re-download packages as needed.", path: yarnCachePath, iconName: "shippingbox.fill", isHighRisk: false),

            // Deep System / High Risk
            CleanableArea(name: "App Containers", description: "Sandboxed data for installed apps.", detailedInfo: "EXTREMELY HIGH RISK. Deleting these resets apps to their factory state, causing total data loss for those apps.", path: appContainersPath, iconName: "cube.box", isHighRisk: true, isExtremelyHighRisk: true),
            CleanableArea(name: "Group Containers", description: "Shared data between related apps.", detailedInfo: "HIGH RISK. Deleting this removes shared preferences and data between apps from the same developer.", path: groupContainersPath, iconName: "square.grid.2x2", isHighRisk: true),
            CleanableArea(name: "Application Support", description: "Core data and settings for user apps.", detailedInfo: "EXTREMELY HIGH RISK. Contains critical app databases and configuration. Deleting this destroys your app setups.", path: applicationSupportPath, iconName: "wrench.and.screwdriver", isHighRisk: true, isExtremelyHighRisk: true),
            CleanableArea(name: "macOS Temp Data", description: "System-managed temporary files (/var/folders).", detailedInfo: "HIGH RISK. Deleting these can cause system instability until your Mac is restarted.", path: varFoldersPath, iconName: "folder.badge.minus", isHighRisk: true),
            CleanableArea(name: "System Caches", description: "System-wide caches (/Library/Caches).", detailedInfo: "HIGH RISK. Contains caches for all users and the system. May require elevated privileges to clean completely.", path: systemCachesPath, iconName: "server.rack", isHighRisk: true),
            CleanableArea(name: "System Logs", description: "System-wide logs (/Library/Logs).", detailedInfo: "HIGH RISK. System-level diagnostic logs.", path: systemLogsPath, iconName: "doc.text", isHighRisk: true),
            CleanableArea(name: "Core Logs", description: "Core Unix logs (/var/log).", detailedInfo: "HIGH RISK. Core system logs. Deleting these removes historical system diagnostic information.", path: varLogPath, iconName: "terminal", isHighRisk: true)
        ]
        
        for i in 0..<self.areas.count {
            self.areas[i].defaultOrder = i
        }
    }
    
    private func sortAreas() {
        switch sortOption {
        case .default, .hideEmpty:
            areas.sort { $0.defaultOrder < $1.defaultOrder }
        case .size:
            areas.sort { $0.sizeBytes > $1.sizeBytes }
        case .title:
            areas.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    
    func fetchDetails(for area: CleanableArea) async -> [FileItem] {
        return await service.getDetails(for: area.path)
    }
    
    func calculateAllSizes() {
        fetchFreeDiskSpace()
        for index in areas.indices {
            calculateSize(for: index)
        }
    }
    
    private func fetchFreeDiskSpace() {
        do {
            let fileURL = URL(fileURLWithPath: "/")
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            let capacity: Int64
            if let important = values.volumeAvailableCapacityForImportantUsage {
                capacity = important
            } else if let regular = values.volumeAvailableCapacity {
                capacity = Int64(regular)
            } else {
                self.freeDiskSpace = "Unknown"
                return
            }
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useAll]
            formatter.countStyle = .file
            self.freeDiskSpace = formatter.string(fromByteCount: capacity)
        } catch {
            self.freeDiskSpace = "Unknown"
        }
    }
    
    private func calculateSize(for index: Int) {
        let areaId = areas[index].id
        let areaPath = areas[index].path
        areas[index].state = .loading
        
        Task {
            let size = await service.calculateSize(for: areaPath)
            if let safeIndex = areas.firstIndex(where: { $0.id == areaId }) {
                areas[safeIndex].sizeBytes = size
                areas[safeIndex].state = .ready
                if sortOption == .size { sortAreas() }
            }
        }
    }
    
    func refreshSize(for area: CleanableArea) {
        fetchFreeDiskSpace()
        if let index = areas.firstIndex(where: { $0.id == area.id }) {
            calculateSize(for: index)
        }
    }

    func cancelClean() {
        activeCleanTask?.cancel()
        isShowingCleanOverlay = false
        isCleaningAll = false
        
        for index in areas.indices {
            if areas[index].state == .cleaning {
                calculateSize(for: index)
            }
        }
    }

    func clean(area: CleanableArea, permanently: Bool) {
        guard let index = areas.firstIndex(where: { $0.id == area.id }) else { return }
        
        areas[index].state = .cleaning
        let areaId = area.id
        let areaPath = area.path
        
        isShowingCleanOverlay = true
        isCleanFinished = false
        cleanLogs = []
        currentCleanProgress = 0.0
        estimatedTimeRemaining = nil
        cleanStartTime = Date()
        
        activeCleanTask = Task { @MainActor in
            do {
                try await service.clean(url: areaPath, permanently: permanently) { url, status, progressVal in
                    Task { @MainActor in
                        self.currentCleanProgress = progressVal
                        if let start = self.cleanStartTime, progressVal > 0 {
                            let elapsed = Date().timeIntervalSince(start)
                            self.estimatedTimeRemaining = (elapsed / progressVal) - elapsed
                        }
                        if let last = self.cleanLogs.last, last.url == url {
                            let currentStatus = self.cleanLogs[self.cleanLogs.count - 1].status
                            if case .deleting = currentStatus {
                                self.cleanLogs[self.cleanLogs.count - 1].status = status
                            } else if case .success = status {
                                self.cleanLogs[self.cleanLogs.count - 1].status = status
                            } else if case .error = status {
                                self.cleanLogs[self.cleanLogs.count - 1].status = status
                            }
                        } else if let index = self.cleanLogs.firstIndex(where: { $0.url == url }) {
                            let currentStatus = self.cleanLogs[index].status
                            if case .deleting = currentStatus {
                                self.cleanLogs[index].status = status
                            } else if case .success = status {
                                self.cleanLogs[index].status = status
                            } else if case .error = status {
                                self.cleanLogs[index].status = status
                            }
                        } else {
                            var size: Int64? = nil
                            if case .deleting(let s) = status { size = s }
                            self.cleanLogs.append(CleanLogItem(url: url, sizeBytes: size, status: status))
                        }
                    }
                }
                if !Task.isCancelled {
                    if let safeIndex = areas.firstIndex(where: { $0.id == areaId }) {
                        areas[safeIndex].sizeBytes = 0
                        areas[safeIndex].state = .cleaned
                        fetchFreeDiskSpace()
                        if sortOption == .size { sortAreas() }
                    }
                    if !permanently {
                        if let trashIndex = self.areas.firstIndex(where: { $0.name == "Trash" }) {
                            self.calculateSize(for: trashIndex)
                        }
                    }
                    isCleanFinished = true
                }
            } catch {
                if !Task.isCancelled {
                    if let safeIndex = areas.firstIndex(where: { $0.id == areaId }) {
                        areas[safeIndex].state = .failed(error.localizedDescription)
                    }
                    isCleanFinished = true
                }
            }
        }
    }
    
    func deleteSpecificItem(item: (url: URL, sizeBytes: Int64), in areaId: UUID, permanently: Bool) async {
        isShowingCleanOverlay = true
        isCleanFinished = false
        cleanLogs = []
        currentCleanProgress = 0.0
        
        activeCleanTask = Task { @MainActor in
            do {
                try await service.deleteItem(at: item.url, permanently: permanently) { updatedUrl, status, progressVal in
                    Task { @MainActor in
                        self.currentCleanProgress = progressVal
                        if let last = self.cleanLogs.last, last.url == updatedUrl {
                            let currentStatus = self.cleanLogs[self.cleanLogs.count - 1].status
                            if case .deleting = currentStatus {
                                self.cleanLogs[self.cleanLogs.count - 1].status = status
                            } else if case .success = status {
                                self.cleanLogs[self.cleanLogs.count - 1].status = status
                            } else if case .error = status {
                                self.cleanLogs[self.cleanLogs.count - 1].status = status
                            }
                        } else if let index = self.cleanLogs.firstIndex(where: { $0.url == updatedUrl }) {
                            let currentStatus = self.cleanLogs[index].status
                            if case .deleting = currentStatus {
                                self.cleanLogs[index].status = status
                            } else if case .success = status {
                                self.cleanLogs[index].status = status
                            } else if case .error = status {
                                self.cleanLogs[index].status = status
                            }
                        } else {
                            self.cleanLogs.append(CleanLogItem(url: updatedUrl, sizeBytes: item.sizeBytes, status: status))
                        }
                    }
                }
            } catch {
                print("Failed to delete specific item: \(error)")
            }
            if !Task.isCancelled {
                if let index = areas.firstIndex(where: { $0.id == areaId }) {
                    calculateSize(for: index)
                }
                if !permanently {
                    if let trashIndex = self.areas.firstIndex(where: { $0.name == "Trash" }) {
                        self.calculateSize(for: trashIndex)
                    }
                }
                fetchFreeDiskSpace()
                isCleanFinished = true
            }
        }
        await activeCleanTask?.value
    }
    
    func deleteSpecificItems(items: [(url: URL, sizeBytes: Int64)], in areaId: UUID, permanently: Bool) async {
        isShowingCleanOverlay = true
        isCleanFinished = false
        cleanLogs = []
        currentCleanProgress = 0.0
        estimatedTimeRemaining = nil
        cleanStartTime = Date()
        
        activeCleanTask = Task { @MainActor in
            let total = Double(items.count)
            for (index, item) in items.enumerated() {
                if Task.isCancelled { break }
                do {
                    try await service.deleteItem(at: item.url, permanently: permanently) { updatedUrl, status, itemProgress in
                        Task { @MainActor in
                            let totalProgress = (Double(index) + itemProgress) / total
                            self.currentCleanProgress = totalProgress
                            if let start = self.cleanStartTime, totalProgress > 0 {
                                let elapsed = Date().timeIntervalSince(start)
                                self.estimatedTimeRemaining = (elapsed / totalProgress) - elapsed
                            }
                            if let last = self.cleanLogs.last, last.url == updatedUrl {
                                let currentStatus = self.cleanLogs[self.cleanLogs.count - 1].status
                                if case .deleting = currentStatus {
                                    self.cleanLogs[self.cleanLogs.count - 1].status = status
                                } else if case .success = status {
                                    self.cleanLogs[self.cleanLogs.count - 1].status = status
                                } else if case .error = status {
                                    self.cleanLogs[self.cleanLogs.count - 1].status = status
                                }
                            } else if let index = self.cleanLogs.firstIndex(where: { $0.url == updatedUrl }) {
                                let currentStatus = self.cleanLogs[index].status
                                if case .deleting = currentStatus {
                                    self.cleanLogs[index].status = status
                                } else if case .success = status {
                                    self.cleanLogs[index].status = status
                                } else if case .error = status {
                                    self.cleanLogs[index].status = status
                                }
                            } else {
                                self.cleanLogs.append(CleanLogItem(url: updatedUrl, sizeBytes: item.sizeBytes, status: status))
                            }
                        }
                    }
                } catch {
                    print("Failed to delete specific item: \(error)")
                }
            }
            if !Task.isCancelled {
                if let index = areas.firstIndex(where: { $0.id == areaId }) {
                    calculateSize(for: index)
                }
                if !permanently {
                    if let trashIndex = self.areas.firstIndex(where: { $0.name == "Trash" }) {
                        self.calculateSize(for: trashIndex)
                    }
                }
                fetchFreeDiskSpace()
                isCleanFinished = true
            }
        }
        await activeCleanTask?.value
    }
    
    func retryItem(url: URL) {
        if let index = cleanLogs.firstIndex(where: { $0.url == url }) {
            cleanLogs[index].status = .deleting(size: cleanLogs[index].sizeBytes)
        }
        Task { @MainActor in
            do {
                try await service.deleteItem(at: url, permanently: true) { updatedUrl, status, _ in
                    Task { @MainActor in
                        if let index = self.cleanLogs.firstIndex(where: { $0.url == updatedUrl }) {
                            self.cleanLogs[index].status = status
                        }
                    }
                }
            } catch {}
        }
    }
    
    func skipItem(url: URL) {
        if let index = cleanLogs.firstIndex(where: { $0.url == url }) {
            cleanLogs[index].status = .error("Skipped by user")
        }
    }
}
