import SwiftUI

struct LyricPrompterView: View {
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = LyricPrompterViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let song = viewModel.currentSong {
                    LyricDisplayView(song: song, viewModel: viewModel)
                } else if !viewModel.searchResults.isEmpty {
                    resultsListView
                } else {
                    songListView
                }
            }
            .navigationTitle(viewModel.currentSong != nil ? (viewModel.currentSong?.title ?? "Lyrics") : "Lyric Prompter")
            .toolbar {
                if viewModel.currentSong != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            viewModel.stopPlayback()
                            viewModel.currentSong = nil
                        }
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onAppear {
            viewModel.bind(settings: settingsStore, openAIStore: openAIStore)
            viewModel.loadSaved()
        }
        .onDisappear {
            viewModel.stopPlayback()
        }
    }

    private var songListView: some View {
        VStack(spacing: 0) {
            if !viewModel.savedSongs.isEmpty {
                List {
                    ForEach(viewModel.savedSongs) { song in
                        Button {
                            viewModel.selectSong(song)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title).font(.headline)
                                Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.deleteSong(song)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .accessibilityAction(named: Text("Delete \(song.title)")) {
                            viewModel.deleteSong(song)
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                Spacer()
                Text("No saved lyrics yet.").foregroundStyle(.secondary)
                Spacer()
            }

            VStack(spacing: 12) {
                TextField("Song title or \"Song - Artist\"", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { Task { await viewModel.search() } }

                Button {
                    Task { await viewModel.search() }
                } label: {
                    Label(viewModel.isSearching ? "Searching..." : "Search Lyrics", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSearching || viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }

    private var resultsListView: some View {
        List {
            Section {
                ForEach(viewModel.searchResults) { result in
                    Button {
                        viewModel.loadSelectedResult(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(result.trackName).font(.headline)
                                Spacer()
                                sourceTag(result.source)
                            }
                            Text(result.artistName).font(.subheadline).foregroundStyle(.secondary)
                            if let album = result.albumName {
                                Text(album).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                if result.hasSyncedLyrics {
                                    Label("Synced", systemImage: "waveform")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                                Label("Plain", systemImage: "text.alignleft")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityHint(result.hasSyncedLyrics ? "Has timed lyrics" : "Plain text lyrics only")
                }
            } header: {
                Text("\(viewModel.searchResults.count) results found")
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { viewModel.dismissResults() }
            }
        }
    }

    private func sourceTag(_ source: LyricSearchSource) -> some View {
        Text(source.rawValue.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(sourceColor(source).opacity(0.2))
            .foregroundStyle(sourceColor(source))
            .clipShape(Capsule())
    }

    private func sourceColor(_ source: LyricSearchSource) -> Color {
        switch source {
        case .lrclib: return .blue
        case .netease: return .red
        case .llm: return .purple
        }
    }
}

private struct LyricDisplayView: View {
    let song: LyricSong
    let viewModel: LyricPrompterViewModel
    @EnvironmentObject private var settingsStore: SettingsStore

    private var advanceOffset: TimeInterval { settingsStore.lyricAdvanceOffset }

    var body: some View {
        VStack(spacing: 0) {
            if song.hasTimestamps {
                HStack(spacing: 12) {
                    Button {
                        viewModel.isPlaying ? viewModel.stopPlayback() : viewModel.playFromStart(offset: advanceOffset)
                    } label: {
                        Label(viewModel.isPlaying ? "Stop" : "Play from Start", systemImage: viewModel.isPlaying ? "stop.circle" : "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.isPlaying ? viewModel.stopPlayback() : viewModel.playFromNow(offset: advanceOffset)
                    } label: {
                        Label(viewModel.isPlaying ? "Stop" : "Play from Now", systemImage: viewModel.isPlaying ? "stop.circle" : "forward.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            } else {
                HStack {
                    Spacer()
                    Text("No timed lyrics available").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.vertical, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(song.lines) { line in
                        Text(line.text)
                            .font(.body)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }

            Button { viewModel.saveCurrentSong() } label: {
                Label("Save Lyrics", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}
