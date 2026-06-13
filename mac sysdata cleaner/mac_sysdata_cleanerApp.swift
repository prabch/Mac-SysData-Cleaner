//
//  mac_sysdata_cleanerApp.swift
//  mac sysdata cleaner
//
//  Created by prabch on 01-06-2026.
//

import SwiftUI
import Foundation
import Combine

// Main enty point for the aplication


@main
struct mac_sysdata_cleanerApp: App {
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var updateChecker = UpdateChecker()
    
    var body: some Scene {
        WindowGroup("Mac SysData Cleaner") {
            ContentView()
                .environmentObject(permissionManager)
                .environmentObject(updateChecker)
                .task {
                    updateChecker.checkForUpdates()
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .configureResizability()
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Mac SysData Cleaner") {
                    let baseFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                    let boldFont = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
                    
                    let text = "A simple, yet powerful system data cleaner for macOS. Use with caution.\n\nCreated by "
                    let credits = NSMutableAttributedString(string: text, attributes: [.font: baseFont])
                    
                    let authorPrab = NSAttributedString(string: "prab", attributes: [.link: URL(string: "https://prabch.com")!, .font: boldFont])
                    let authorCh = NSAttributedString(string: "ch\n\n", attributes: [.link: URL(string: "https://prabch.com")!, .font: baseFont])
                    credits.append(authorPrab)
                    credits.append(authorCh)
                    
                    let githubLink = NSAttributedString(string: "GitHub", attributes: [.link: URL(string: "https://github.com/prabch/Mac-SysData-Cleaner")!, .font: baseFont])
                    credits.append(githubLink)
                    
                    credits.append(NSAttributedString(string: "  •  ", attributes: [.font: baseFont]))
                    
                    let websiteLink = NSAttributedString(string: "Website", attributes: [.link: URL(string: "https://prabch.com/mac-sysdata-cleaner")!, .font: baseFont])
                    credits.append(websiteLink)
                    
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    credits.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: credits.length))
                    
                    var options: [NSApplication.AboutPanelOptionKey: Any] = [
                        .credits: credits,
                        .applicationName: "Mac SysData Cleaner",
                        .version: ""
                    ]
                    
                    if let appIcon = NSImage(named: "AppIcon") {
                        options[.applicationIcon] = appIcon
                    }
                    
                    NSApplication.shared.orderFrontStandardAboutPanel(options: options)
                }
            }
        }
    }
}

extension Scene {
    func configureResizability() -> some Scene {
        if #available(macOS 13.0, *) {
            return self.windowResizability(.contentSize)
        } else {
            return self
        }
    }
}

