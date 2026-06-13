//
//  AreaRowView.swift
//  mac sysdata cleaner
//
//  Created by prabch on 10-05-2026.
//

import SwiftUI

// Represnts a single row in the cleaner lisst
struct AreaRowView: View {
    let area: CleanableArea
    let onClean: (Bool) -> Void
    let onFetchDetails: () async -> [FileItem]
    let onDeleteItem: (URL, Bool) async -> Void
    let onRefresh: () -> Void
    
    @State private var showInfo = false
    @State private var showCleanAlert = false
    @State private var showSecondCleanAlert = false
    @State private var pendingCleanPermanently = false
    @EnvironmentObject var viewModel: CleanerViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            
            // Icon
            Image(systemName: area.iconName)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if area.isExtremelyHighRisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .help("Extremely High Risk Data")
                    } else if area.isHighRisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .help("High Risk Data")
                    }
                    
                    Text(area.name)
                        .font(.headline)
                    
                    Button(action: { showInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInfo) {
                        Text(area.detailedInfo)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding()
                            .frame(width: 300)
                    }
                }
                
                Text(area.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // State
            HStack(spacing: 16) {
                if area.state == .loading || area.state == .cleaning {
                    ProgressView()
                        .controlSize(.small)
                } else if area.state == .cleaned {
                    Text("Cleaned")
                        .foregroundColor(.green)
                        .font(.subheadline)
                } else {
                    Text(area.formattedSize)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Button(action: {
                        onRefresh()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(area.state == .loading || area.state == .cleaning ? .secondary.opacity(0.5) : .secondary)
                    .disabled(area.state == .loading || area.state == .cleaning)
                    .padding(.trailing, 4)
                    
                    Button(action: {
                        viewModel.detailsItems = nil
                        viewModel.selectedAreaForDetails = area
                        Task {
                            viewModel.detailsItems = await onFetchDetails()
                        }
                    }) {
                        Text("Details")
                            .frame(minWidth: 50)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!area.state.canClean || area.sizeBytes == 0)
                    
                    Button(action: {
                        showCleanAlert = true
                    }) {
                        Text(area.state == .cleaned ? "Cleaned" : "Clean")
                            .frame(minWidth: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!area.state.canClean || area.sizeBytes == 0)
                    .confirmationDialog(
                        "Are you sure you want to clean \(area.name)?",
                        isPresented: $showCleanAlert,
                        titleVisibility: .visible
                    ) {
                        if area.name != "Trash" {
                            Button("Move to Trash") {
                                if area.isHighRisk {
                                    pendingCleanPermanently = false
                                    showSecondCleanAlert = true
                                } else {
                                    onClean(false)
                                }
                            }
                        }
                        Button("Delete Permanently", role: .destructive) {
                            if area.isHighRisk {
                                pendingCleanPermanently = true
                                showSecondCleanAlert = true
                                } else {
                                onClean(true)
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                    .alert(
                        "CRITICAL WARNING",
                        isPresented: $showSecondCleanAlert
                    ) {
                        Button("Cancel", role: .cancel) {}
                        Button("Proceed", role: .destructive) {
                            onClean(pendingCleanPermanently)
                        }
                    } message: {
                        Text("Deleting data from \(area.name) is high risk and may cause apps to lose data or system instability. Please ensure you have a backup. Proceed at your own risk. Do you still wish to proceed?")
                    }
                }
            }
        }
    }
}
