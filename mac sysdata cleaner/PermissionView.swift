//
//  PermissionView.swift
//  mac sysdata cleaner
//
//  Created by prabch on 01-05-2026.
//

import SwiftUI

// Viw to display instuctions on how to grant full disk acess
struct PermissionView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with Icon and Text
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "lock.square")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Full Disk Access Required")
                        .font(.headline)
                    
                    Text("Mac SysData Cleaner needs Full Disk Access to accurately scan and clean system caches, Xcode derived data, and other protected folders.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("How to grant access:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Click **Open System Settings** below.")
                    Text("2. Find **Mac SysData Cleaner** in the list.")
                    Text("3. Toggle the switch to ON.")
                    Text("4. Click **Check Again** to refresh.")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding(.leading, 64) // Align with the text above
            
            Spacer()
            
            // Native Bottom Button Bar
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Check Again") {
                    permissionManager.checkFullDiskAccess()
                    if permissionManager.hasFullDiskAccess {
                        dismiss()
                    }
                }
                
                Button("Open System Settings") {
                    permissionManager.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 300)
    }
}

#if swift(>=5.9)
#Preview {
    PermissionView()
        .environmentObject(PermissionManager())
}
#endif
