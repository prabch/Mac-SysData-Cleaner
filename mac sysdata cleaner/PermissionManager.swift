//
//  PermissionManager.swift
//  mac sysdata cleaner
//
//  Created by prabch on 02-04-2026.
//

import Foundation
import AppKit
import SwiftUI
import Combine

// Manger class that handls checking for disk permisions
class PermissionManager: ObservableObject {
    @Published var hasFullDiskAccess: Bool = false
    
    init() {
        checkFullDiskAccess()
    }
    
    // Checks if the user has greanted ful disk access in system setings
    func checkFullDiskAccess() {
        // macOS protects several user directories. 
        // We attempt to open known protected directories/files to see if we get a permission denied error.
        let pathsToCheck = [
            NSHomeDirectory() + "/Library/Messages",
            NSHomeDirectory() + "/Library/Mail",
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist"
        ]
        
        for path in pathsToCheck {
            let fd = open(path, O_RDONLY)
            if fd != -1 {
                // Successfully opened a protected file/dir -> We have access
                close(fd)
                hasFullDiskAccess = true
                return
            } else if errno == EPERM || errno == EACCES {
                // Permission denied -> We don't have Full Disk Access
                hasFullDiskAccess = false
                return
            }
        }
        
        // If we get here, the files might not exist on this specific machine. 
        // We'll optimistically allow access, as it's better than blocking the app entirely.
        hasFullDiskAccess = true
    }
    
    func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
