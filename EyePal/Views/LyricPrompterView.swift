import SwiftUI

struct LyricPrompterView: View {
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = LyricPrompterViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let song = viewModel.currentSong {
                    LyricDisplayView(
                        song: song,
                        viewModel: viewModel
                    )
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
                                Text(song.title)
                                    .font(.headline)
                                Text(song.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
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
                Text("No saved lyrics yet.")
                    .foregroundStyle(.secondary)
                Spacer()
            }

            VStack(spacing: 12) {
                TextField("Song title", text: $viewModel.songTitle)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.next)

                TextField("Artist", text: $viewModel.artistName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.search() }
                    }

                Button {
                    Task { await viewModel.search() }
                } label: {
                    Label(
                        viewModel.isSearching ? "Searching..." : "Search Lyrics",
                        systemImage: "magnifyingglass"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSearching || viewModel.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }
}

private struct LyricDisplayView: View {
    let song: LyricSong
    let viewModel: LyricPrompterViewModel
    @EnvironmentObject private var settingsStore: SettingsStore

    private var advanceOffset: TimeInterval {
        settingsStore.lyricAdvanceOffset
    }

    var body: some View {
        VStack(spacing: 0) {
            if song.hasTimestamps {
                HStack(spacing: 12) {
                    Button {
                        if viewModel.isPlaying {
                            viewModel.stopPlayback()
                        } else {
                            viewModel.playFromStart(offset: advanceOffset)
                        }
                    } label: {
                        Label(
                            viewModel.isPlaying ? "Stop" : "Play from Start",
                            systemImage: viewModel.isPlaying ? "stop.circle" : "play.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Plays lyrics from the beginning with timing")

                    Button {
                        if viewModel.isPlaying {
                            viewModel.stopPlayback()
                        } else {
                            viewModel.playFromNow(offset: advanceOffset)
                        }
                    } label: {
                        Label(
                            viewModel.isPlaying ? "Stop" : "Play from Now",
                            systemImage: viewModel.isPlaying ? "stop.circle" : "forward.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Plays lyrics starting from the first line immediately")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            } else {
                HStack {
                    Spacer()
                    Text("No timed lyrics available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(song.lines) { line in
                        HStack(alignment: .top, spacing: 8) {
                            if let time = line.startTime {
                                Text(formatTime(time))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }

                            Text(line.text)
                                .font(.body)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }

            Button {
                viewModel.saveCurrentSong()
            } label: {
                Label("Save Lyrics", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
