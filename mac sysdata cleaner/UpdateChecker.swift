//
//  UpdateChecker.swift
//  mac sysdata cleaner
//
//  Created by prabch on 10-04-2026.
//

import Foundation
import Combine

// Handls checking for latest GitHub releas
class UpdateChecker: ObservableObject {
    @Published var isUpdateAvailable = false
    @Published var latestVersion = ""
    @Published var releaseURL: URL?
    
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    
    // Check GitHub API for updates asyncronously
    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/prabch/Mac-SysData-Cleaner/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let tagName = json["tag_name"] as? String,
               let htmlUrlString = json["html_url"] as? String {
                
                // Remove 'v' prefix if present for comparison
                let latest = tagName.replacingOccurrences(of: "v", with: "")
                let current = self.currentVersion.replacingOccurrences(of: "v", with: "")
                
                DispatchQueue.main.async {
                    if latest.compare(current, options: .numeric) == .orderedDescending {
                        self.latestVersion = tagName
                        self.releaseURL = URL(string: htmlUrlString)
                        self.isUpdateAvailable = true
                    }
                }
            }
        }.resume()
    }
}
