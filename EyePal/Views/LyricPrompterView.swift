import SwiftUI
import UIKit

enum LyricNavigationState {
    case search
    case results
    case lyrics
}

struct LyricPrompterView: View {
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = LyricPrompterViewModel()
    @State private var navState: LyricNavigationState = .search
    @State private var showLyricsSheet = false

    var body: some View {
        NavigationStack {
            Group {
                switch navState {
                case .search: songListView
                case .results: resultsListView
                case .lyrics: EmptyView()
                }
            }
            .navigationTitle(titleForState)
            .onAppear {
                viewModel.bind(settings: settingsStore, openAIStore: openAIStore)
                viewModel.loadSaved()
            }
            .sheet(isPresented: $showLyricsSheet) {
                if let song = viewModel.currentSong {
                    LyricDisplayView(song: song, viewModel: viewModel)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }

    private var titleForState: String {
        switch navState {
        case .search: return "Lyric Prompter"
        case .results: return "Search Results"
        case .lyrics: return viewModel.currentSong?.title ?? "Lyrics"
        }
    }

    private var songListView: some View {
        VStack(spacing: 0) {
            if !viewModel.savedSongs.isEmpty {
                List {
                    ForEach(viewModel.savedSongs) { song in
                        Button {
                            viewModel.selectSong(song)
                            viewModel.currentSong = song
                            navState = .lyrics
                            showLyricsSheet = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title).font(.headline)
                                Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { viewModel.deleteSong(song) } label: { Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash") }
                        }
                    }
                }.listStyle(.plain)
            } else {
                Spacer()
                Text("No saved lyrics yet.").foregroundStyle(.secondary)
                Spacer()
            }

            VStack(spacing: 12) {
                TextField("Song title or \"Song - Artist\"", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { Task { await performSearch() } }

                Button { Task { await performSearch() } } label: {
                    Label(viewModel.isSearching ? "Searching..." : "Search Lyrics", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSearching || viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }

    private func performSearch() async {
        await viewModel.search()
        if !viewModel.searchResults.isEmpty {
            navState = .results
        }
    }

    private var resultsListView: some View {
        List {
            Section {
                ForEach(viewModel.searchResults) { result in
                    Button {
                        viewModel.loadSelectedResult(result)
                        viewModel.currentSong = viewModel.currentSong
                        navState = .lyrics
                        showLyricsSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(result.trackName).font(.headline)
                                Spacer()
                                Text(result.source.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2)).clipShape(Capsule())
                            }
                            Text(result.artistName).font(.subheadline).foregroundStyle(.secondary)
                            if let album = result.albumName { Text(album).font(.caption).foregroundStyle(.secondary) }
                            HStack(spacing: 8) {
                                if result.hasSyncedLyrics { Label("Synced", systemImage: "waveform").font(.caption).foregroundStyle(.green) }
                                else { Label("Plain", systemImage: "text.alignleft").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            } header: { Text("\(viewModel.searchResults.count) results found") }

            if !viewModel.searchLog.isEmpty {
                Section("Debug Log") {
                    ForEach(viewModel.searchLog, id: \.self) { entry in
                        Text(entry).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("voiceover.back", comment: "")) { navState = .search; viewModel.dismissResults() }
            }
        }
    }
}

private struct LyricDisplayView: View {
    let song: LyricSong
    let viewModel: LyricPrompterViewModel
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if song.hasTimestamps {
                    HStack(spacing: 12) {
                        Button { viewModel.isPlaying ? viewModel.stopPlayback() : viewModel.playFromStart(offset: settingsStore.lyricAdvanceOffset) } label: {
                            Label(viewModel.isPlaying ? "Stop" : "Play from Start", systemImage: viewModel.isPlaying ? "stop.circle" : "play.circle").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                        Button { viewModel.isPlaying ? viewModel.stopPlayback() : viewModel.playFromNow(offset: settingsStore.lyricAdvanceOffset) } label: {
                            Label(viewModel.isPlaying ? "Stop" : "Play from Now", systemImage: viewModel.isPlaying ? "stop.circle" : "forward.circle").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }.padding(.horizontal).padding(.vertical, 8)
                } else {
                    HStack { Spacer(); Text("No timed lyrics available").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.vertical, 8)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(song.lines) { line in
                            Text(line.text).font(.body).padding(.horizontal)
                        }
                    }.padding(.vertical)
                }

                Button { viewModel.saveCurrentSong(); dismiss() } label: { Label("Save Lyrics", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).padding()
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.close", comment: "")) {
                        viewModel.stopPlayback()
                        dismiss()
                    }
                }
            }
            .onChange(of: viewModel.isPlaying) { playing in
                if playing, let firstLine = song.lines.first?.text {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        UIAccessibility.post(notification: .screenChanged, argument: nil)
                        UIAccessibility.post(notification: .announcement, argument: firstLine)
                    }
                }
            }
        }
    }
}
