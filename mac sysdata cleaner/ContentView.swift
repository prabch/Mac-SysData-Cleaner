//
//  ContentView.swift
//  mac sysdata cleaner
//
//  Created by prabch on 13-06-2026.
//

import SwiftUI

// Main content view for the appications manging overal layout
struct ContentView: View {
    @StateObject private var viewModel = CleanerViewModel()
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var updateChecker: UpdateChecker
    @State private var showPermissionSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac SysData Cleaner")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 16) {
                        if viewModel.hasActionableAreas {
                            Text("Cleanable: \(viewModel.formattedTotalSize)")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Reclaim disk space by cleaning up unnecessary files.")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 4) {
                            Text("Free Storage: \(viewModel.freeDiskSpace)")
                                .foregroundColor(.secondary)
                            ProgressView()
                                .controlSize(.small)
                                .opacity(viewModel.isAnyLoading ? 1 : 0)
                        }
                    }
                    .font(.subheadline)
                }
                Spacer()
                
                HStack(spacing: 8) {
                    Picker("Sort", selection: $viewModel.sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                    
                    Button(action: {
                        viewModel.calculateAllSizes()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh sizes")
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isCleaningAll)
                }
                
                // Bulk deletion removed from main view
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if !permissionManager.hasFullDiskAccess {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Some system folders cannot be fully scanned without Full Disk Access.")
                        .font(.subheadline)
                    Spacer()
                    Button("Grant Access") {
                        showPermissionSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.1))
                
                Divider()
            }
            
            // List of Areas
            List {
                ForEach(viewModel.areas) { area in
                    if viewModel.sortOption != .hideEmpty || (area.state.canClean && area.sizeBytes > 0) {
                        AreaRowView(
                            area: area,
                            onClean: { permanently in viewModel.clean(area: area, permanently: permanently) },
                            onFetchDetails: { await viewModel.fetchDetails(for: area) },
                            onDeleteItem: { url, permanently in
                                await viewModel.deleteSpecificItem(item: (url: url, sizeBytes: 0), in: area.id, permanently: permanently)
                            },
                            onRefresh: { viewModel.refreshSize(for: area) }
                        )
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.inset)
            .disabled(viewModel.isShowingCleanOverlay)
        }
        .frame(minWidth: 840, maxWidth: 840, minHeight: 600, maxHeight: 1650)
        .overlay {
            if viewModel.isShowingCleanOverlay && viewModel.selectedAreaForDetails == nil {
                CleanProgressOverlayView(viewModel: viewModel)
            }
        }
        .sheet(item: $viewModel.selectedAreaForDetails) { area in
            DetailsSheetView(
                area: area,
                items: $viewModel.detailsItems,
                isPresented: Binding(
                    get: { viewModel.selectedAreaForDetails != nil },
                    set: { if !$0 { viewModel.selectedAreaForDetails = nil } }
                ),
                onFetchDetails: { await viewModel.fetchDetails(for: area) },
                onDeleteItem: { url, permanently in
                    await viewModel.deleteSpecificItem(item: (url: url, sizeBytes: 0), in: area.id, permanently: permanently)
                }
            )
        }
        .sheet(isPresented: $showPermissionSheet) {
            PermissionView()
                .environmentObject(permissionManager)
        }
        .alert("Update Available", isPresented: $updateChecker.isUpdateAvailable) {
            Button("Download") {
                if let url = updateChecker.releaseURL {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Version \(updateChecker.latestVersion) of Mac SysData Cleaner is available. Would you like to download it now?")
        }
        .environmentObject(viewModel)
    }
}


#if swift(>=5.9)
#Preview {
    ContentView()
}
#else
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif

