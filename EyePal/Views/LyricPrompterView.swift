import SwiftUI

enum LyricFocusTarget {
    case pageTitle
    case firstLine
}

struct LyricPrompterView: View {
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = LyricPrompterViewModel()
    @AccessibilityFocusState private var focus: LyricFocusTarget?

    var body: some View {
        NavigationStack {
            Group {
                if let song = viewModel.currentSong {
                    LyricDisplayView(song: song, viewModel: viewModel, focus: $focus)
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
            if viewModel.currentSong != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focus = .pageTitle
                }
            }
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
                                SuggestionChip(onClick: {}, label: { Text(result.source) })
                            }
                            Text(result.artistName).font(.subheadline).foregroundStyle(.secondary)
                            if let album = result.albumName {
                                Text(album).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                if result.hasSyncedLyrics {
                                    Label("Synced", systemImage: "waveform").font(.caption).foregroundStyle(.green)
                                } else {
                                    Label("Plain", systemImage: "text.alignleft").font(.caption).foregroundStyle(.secondary)
                                }
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
}

private struct LyricDisplayView: View {
    let song: LyricSong
    let viewModel: LyricPrompterViewModel
    @Binding var focus: LyricFocusTarget?

    private var advanceOffset: TimeInterval { settingsStore.lyricAdvanceOffset }

    @EnvironmentObject private var settingsStore: SettingsStore

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
                    Text("No timed lyrics available").font(.bodySmall).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.vertical, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(song.lines.enumerated()), id: \.element.id) { index, line in
                            Text(line.text)
                                .font(.body)
                                .padding(.horizontal)
                                .id("line_\(index)")
                                .if(index == 0) { view in
                                    view.accessibilityFocused($focus, equals: .firstLine)
                                }
                        }
                    }
                    .padding(.vertical)
                }
            }

            Button { viewModel.saveCurrentSong() } label: {
                Label("Save Lyrics", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .onChange(of: viewModel.isPlaying) { playing in
            if playing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focus = .firstLine
                }
            }
        }
    }
}
