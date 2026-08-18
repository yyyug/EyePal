import SwiftUI
import UIKit

struct LyricPrompterView: View {
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = LyricPrompterViewModel()
    @State private var showResults = false
    @State private var showLyricsSheet = false

    var body: some View {
        NavigationStack {
            songListView
                .navigationDestination(isPresented: $showResults) {
                    resultsListView
                }
                .onAppear {
                    viewModel.bind(settings: settingsStore, openAIStore: openAIStore)
                    viewModel.loadSaved()
                }
                .alert(NSLocalizedString("common.error", comment: ""), isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )) {
                    Button(NSLocalizedString("common.ok", comment: "")) { viewModel.errorMessage = nil }
                } message: { Text(viewModel.errorMessage ?? "") }
        }
        .sheet(isPresented: $showLyricsSheet) {
            if let song = viewModel.currentSong {
                LyricDisplayView(song: song, viewModel: viewModel)
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
                            viewModel.currentSong = song
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
                Text(NSLocalizedString("lyric.noSaved", comment: "")).foregroundStyle(.secondary)
                Spacer()
            }

            VStack(spacing: 12) {
                TextField(NSLocalizedString("lyric.searchPlaceholder", comment: ""), text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { Task { await performSearch() } }

                Button { Task { await performSearch() } } label: {
                    Label(viewModel.isSearching ? NSLocalizedString("lyric.searching", comment: "") : NSLocalizedString("lyric.searchLyrics", comment: ""), systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSearching || viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(NSLocalizedString("feature.lyricPrompter", comment: ""))
    }

    private func performSearch() async {
        await viewModel.search()
        if !viewModel.searchResults.isEmpty {
            showResults = true
        }
    }

    private var resultsListView: some View {
        List {
            Section {
                ForEach(viewModel.searchResults) { result in
                    Button {
                        viewModel.loadSelectedResult(result)
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
                                if result.hasSyncedLyrics { Label(NSLocalizedString("lyric.synced", comment: ""), systemImage: "waveform").font(.caption).foregroundStyle(.green) }
                                else { Label(NSLocalizedString("lyric.plain", comment: ""), systemImage: "text.alignleft").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            } header: { Text("\(viewModel.searchResults.count) \(NSLocalizedString("lyric.resultsFound", comment: ""))") }

            if !viewModel.searchLog.isEmpty {
                Section(NSLocalizedString("lyric.debugLog", comment: "")) {
                    ForEach(viewModel.searchLog, id: \.self) { entry in
                        Text(entry).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(NSLocalizedString("lyric.searchResults", comment: ""))
    }
}

private struct LyricDisplayView: View {
    let song: LyricSong
    let viewModel: LyricPrompterViewModel
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusedLineID: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if song.hasTimestamps {
                    HStack(spacing: 12) {
                        Button { viewModel.isPlaying ? viewModel.stopPlayback() : viewModel.playFromStart(offset: settingsStore.lyricAdvanceOffset) } label: {
                            Label(viewModel.isPlaying ? NSLocalizedString("common.stop", comment: "") : NSLocalizedString("lyric.playFromStart", comment: ""), systemImage: viewModel.isPlaying ? "stop.circle" : "play.circle").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                        Button { viewModel.isPlaying ? viewModel.stopPlayback() : viewModel.playFromNow(offset: settingsStore.lyricAdvanceOffset) } label: {
                            Label(viewModel.isPlaying ? NSLocalizedString("common.stop", comment: "") : NSLocalizedString("lyric.playFromNow", comment: ""), systemImage: viewModel.isPlaying ? "stop.circle" : "forward.circle").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }.padding(.horizontal).padding(.vertical, 8)
                } else {
                    HStack { Spacer(); Text(NSLocalizedString("lyric.noTimedLyrics", comment: "")).font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.vertical, 8)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(song.lines) { line in
                            Text(line.text)
                                .font(.body)
                                .padding(.horizontal)
                                .id(line.id)
                                .accessibilityFocused($focusedLineID, equals: line.id.uuidString)
                        }
                    }
                    .padding(.vertical)
                }

                Button { viewModel.saveCurrentSong(); dismiss() } label: { Label(NSLocalizedString("lyric.saveLyrics", comment: ""), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).padding()
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        viewModel.stopPlayback()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel(NSLocalizedString("common.close", comment: ""))
                    }
                }
            }
            .onChange(of: viewModel.isPlaying) { playing in
                if playing, let firstLine = song.lines.first {
                    focusedLineID = firstLine.id.uuidString
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        UIAccessibility.post(notification: .announcement, argument: firstLine.text)
                    }
                }
            }
        }
    }
}
