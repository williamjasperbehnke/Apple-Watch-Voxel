import SwiftUI

struct ContentView: View {
    @State private var worlds: [String] = []
    @State private var newWorldName = ""
    @State private var path: [String] = []
    @State private var exportMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                List {
                    ForEach(worlds, id: \.self) { world in
                        NavigationLink(value: world) {
                            Text(world)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                exportWorld(named: world)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete(perform: deleteWorlds)
                }
                .padding(.bottom, 85)

                HStack(spacing: 6) {
                    TextField("New world", text: $newWorldName)
                    Button {
                        let worldID = WorldLibrary.createWorld(named: newWorldName)
                        newWorldName = ""
                        refreshWorlds()
                        path.append(worldID)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .font(.caption2)
                    .frame(width: 26)
                }
                .padding(.bottom, 25)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .onAppear {
                refreshWorlds()
            }
            .navigationDestination(for: String.self) { worldID in
                GameView(worldID: worldID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Exports") {
                        ExportListView()
                    }
                }
            }
        }
        .alert("Export", isPresented: Binding(
            get: { exportMessage != nil },
            set: { _ in exportMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private func refreshWorlds() {
        WorldLibrary.bootstrapSampleWorlds()
        worlds = WorldLibrary.listWorlds()
    }

    private func deleteWorlds(at offsets: IndexSet) {
        let names = offsets.map { worlds[$0] }
        for name in names {
            WorldLibrary.deleteWorld(named: name)
        }
        refreshWorlds()
    }

    private func exportWorld(named name: String) {
        if let url = WorldLibrary.exportWorldPNG(named: name) {
            exportMessage = "Saved PNG to \(url.lastPathComponent)."
        } else {
            exportMessage = "Failed to export \(name)."
        }
    }
}

#Preview {
    ContentView()
}
