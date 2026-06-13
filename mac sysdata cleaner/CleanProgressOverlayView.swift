//
//  CleanProgressOverlayView.swift
//  mac sysdata cleaner
//
//  Created by prabch on 15-05-2026.
//

import SwiftUI

// Ovrlay view displayed whlie cleaning is in progrss
struct CleanProgressOverlayView: View {
    @ObservedObject var viewModel: CleanerViewModel
    
    var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Processing Deletions...")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text("\(Int(viewModel.currentCleanProgress * 100))%")
                            .font(.subheadline).bold()
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if viewModel.isCleanFinished {
                            Text("Freed: \(formatBytes(viewModel.totalFreedBytes))")
                                .font(.subheadline).bold()
                                .foregroundColor(.green)
                        } else {
                            Text(formatTime(viewModel.estimatedTimeRemaining))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: 340)
                    
                    ProgressView(value: viewModel.currentCleanProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(maxWidth: 340)
                        .scaleEffect(x: 1, y: 0.6, anchor: .center)
                }
                
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.cleanLogs) { log in
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(log.url.path)
                                        .font(.footnote)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    
                                    if case .error(let msg) = log.status {
                                        Text(msg)
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                            .lineLimit(3)
                                    } else if let size = log.sizeBytes {
                                        Text(formatBytes(size))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                LogStatusIconView(log: log, viewModel: viewModel)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
                
                if viewModel.isCleanFinished {
                    Button("Close") {
                        viewModel.isShowingCleanOverlay = false
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        viewModel.cancelClean()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(32)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
            .frame(maxWidth: 600)
        }
    }
    
    // Formatr for time esstimate
    private func formatTime(_ time: TimeInterval?) -> String {
        guard let time = time, time.isFinite, !time.isNaN, time > 0 else { return "Calculating..." }
        if time < 60 {
            return "\(Int(time))s remaining"
        } else {
            let mins = Int(time) / 60
            let secs = Int(time) % 60
            return "\(mins)m \(secs)s remaining"
        }
    }
    
    // Formatr for byte cout
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// Icon idicating status of log itm
struct LogStatusIconView: View {
    let log: CleanLogItem
    @ObservedObject var viewModel: CleanerViewModel
    @State private var isHovered = false
    
    var body: some View {
        ZStack(alignment: .center) {
            switch log.status {
            case .deleting:
                if isHovered {
                    Button(action: {
                        viewModel.skipItem(url: log.url)
                    }) {
                        Text("Skip")
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .error:
                if isHovered {
                    Button(action: {
                        viewModel.retryItem(url: log.url)
                    }) {
                        Text("Retry")
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .frame(width: 44, height: 24, alignment: .center)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
