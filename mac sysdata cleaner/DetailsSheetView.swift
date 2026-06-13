//
//  DetailsSheetView.swift
//  mac sysdata cleaner
//
//  Created by prabch on 12-05-2026.
//

import SwiftUI

// Viw to show the detils of a sepcific cleanable area
struct DetailsSheetView: View {
    let area: CleanableArea
    @Binding var items: [FileItem]?
    @Binding var isPresented: Bool
    let onFetchDetails: () async -> [FileItem]
    let onDeleteItem: (URL, Bool) async -> Void
    
    @EnvironmentObject var viewModel: CleanerViewModel
    
    @State private var showCleanSelectedAlert = false
    @State private var showDeleteSingleAlert = false
    @State private var itemToDelete: UUID?
    @State private var selectedItemIDs = Set<UUID>()
    @State private var searchText = ""
    
    private enum FocusField {
        case dummy
        case search
    }
    @FocusState private var focusedField: FocusField?
    
    var selectedCount: Int {
        selectedItemIDs.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(area.name)
                    .font(.headline)
                Spacer()
                
                Group {
                    TextField("", text: .constant(""))
                        .focused($focusedField, equals: .dummy)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        
                    TextField("Search", text: $searchText)
                        .focused($focusedField, equals: .search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        
                    if selectedCount == 0 {
                        Button(action: {
                            showCleanSelectedAlert = true
                        }) {
                            Text("Clean Selected")
                        }
                        .buttonStyle(.bordered)
                        .disabled(true)
                    } else {
                        Button(action: {
                            showCleanSelectedAlert = true
                        }) {
                            Text("Clean Selected (\(selectedCount))")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .confirmationDialog(
                    "Delete \(selectedCount) selected items?",
                    isPresented: $showCleanSelectedAlert,
                    titleVisibility: .visible
                ) {
                    if area.name != "Trash" {
                        Button("Move to Trash") {
                            deleteSelectedItems(permanently: false)
                        }
                    }
                    Button("Delete Permanently", role: .destructive) {
                        deleteSelectedItems(permanently: true)
                    }
                    Button("Cancel", role: .cancel) {}
                }
                
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if let safeItems = items {
                if safeItems.isEmpty {
                    VStack {
                        Spacer()
                        Text("No items found.")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    List(selection: $selectedItemIDs) {
                        ForEach($items.toUnwrapped(defaultValue: [])) { $item in
                            if searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText) {
                                HStack {
                                    Toggle("", isOn: Binding(
                                        get: { selectedItemIDs.contains(item.id) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedItemIDs.insert(item.id)
                                            } else {
                                                selectedItemIDs.remove(item.id)
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                    
                                    Image(systemName: "doc")
                                        .foregroundColor(.secondary)
                                    Text(item.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    
                                    if item.isDeleting {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text(item.formattedSize)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .contextMenu {
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
                                    }
                                    
                                    Divider()
                                    
                                    Button("Search Filename on Google") {
                                        if let query = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                           let url = URL(string: "https://www.google.com/search?q=\(query)") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    
                                    Button("Search Path on Google") {
                                        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
                                        let fullPath = item.url.path
                                        let relativePath = fullPath.hasPrefix(homePath) ? "~" + fullPath.dropFirst(homePath.count) : fullPath
                                        
                                        if let query = relativePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                           let url = URL(string: "https://www.google.com/search?q=\(query)") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive, action: {
                                        itemToDelete = item.id
                                        showDeleteSingleAlert = true
                                    }) {
                                        Text("Delete Item")
                                        Image(systemName: "trash")
                                    }
                                } // contextMenu
                                .tag(item.id)
                            }
                        } // ForEach
                    } // List
                    .listStyle(.inset)
                    .confirmationDialog(
                        "Delete this item?",
                        isPresented: $showDeleteSingleAlert,
                        titleVisibility: .visible
                    ) {
                        if area.name != "Trash" {
                            Button("Move to Trash") {
                                if let id = itemToDelete, let item = items?.first(where: { $0.id == id }) {
                                    deleteSingleItem(item: item, permanently: false)
                                }
                            }
                        }
                        Button("Delete Permanently", role: .destructive) {
                            if let id = itemToDelete, let item = items?.first(where: { $0.id == id }) {
                                deleteSingleItem(item: item, permanently: true)
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            } else {
                VStack {
                    Spacer()
                    ProgressView("Loading details...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .disabled(viewModel.isShowingCleanOverlay)
        .frame(width: 550, height: 400)
        .overlay {
            if viewModel.isShowingCleanOverlay {
                CleanProgressOverlayView(viewModel: viewModel)
            }
        }
        .onAppear {
            focusedField = .dummy
        }
    }
    
    // Helpfunc to delete singe item
    private func deleteSingleItem(item: FileItem, permanently: Bool) {
        guard let index = items?.firstIndex(where: { $0.id == item.id }) else { return }
        items?[index].isDeleting = true
        
        Task {
            await viewModel.deleteSpecificItem(item: (url: item.url, sizeBytes: item.sizeBytes), in: area.id, permanently: permanently)
            items = await onFetchDetails()
        }
    }
    
    // Deleets selected items from the list
    private func deleteSelectedItems(permanently: Bool) {
        guard let itemsToProcess = items else { return }
        
        var itemsToDelete: [(url: URL, sizeBytes: Int64)] = []
        for i in itemsToProcess.indices where selectedItemIDs.contains(itemsToProcess[i].id) {
            items?[i].isDeleting = true
            itemsToDelete.append((url: itemsToProcess[i].url, sizeBytes: itemsToProcess[i].sizeBytes))
        }
        
        guard !itemsToDelete.isEmpty else { return }
        
        Task {
            await viewModel.deleteSpecificItems(items: itemsToDelete, in: area.id, permanently: permanently)
            items = await onFetchDetails()
            selectedItemIDs.removeAll()
        }
    }
}

// Helper to use Binding<[T]?> with List
extension Binding {
    func toUnwrapped<T>(defaultValue: [T]) -> Binding<[T]> where Value == [T]? {
        Binding<[T]>(
            get: { self.wrappedValue ?? defaultValue },
            set: { self.wrappedValue = $0 }
        )
    }
}
