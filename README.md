# Fugue

A macOS MIDI player and library manager built with SwiftUI. Fugue lets you import, organize, and play MIDI files with real-time piano roll visualization and per-track instrument control.

## Features

- **Library Management** — Import MIDI files (move or copy), browse by artist/album/genre, search and sort
- **Playlists** — Create and manage custom playlists with drag-and-drop ordering
- **Playback** — Full transport controls (play/pause/stop/seek) powered by AudioToolbox's MusicPlayer
- **Per-Track Muting** — Instantly mute/unmute individual instrument tracks during playback with no interruption
- **Real-Time Visualization** — Piano roll and keyboard views showing notes as they play, colored by MIDI channel
- **Metadata Editing** — Edit title, artist, album, and genre directly in the detail panel
- **Track Inspector** — View all MIDI tracks grouped into Instruments and System Channels with track numbers and channel colors
- **Play Count Tracking** — Automatically counts completed plays per song

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI |
| Data | SwiftData |
| Audio | AudioToolbox (MusicPlayer / MusicSequence) |
| MIDI Parsing | MIDIKitSMF |
| Platform | macOS |

## Architecture

- **PlaybackService** — Manages MusicPlayer/MusicSequence lifecycle, playback state, position tracking, and real-time track muting
- **LibraryManager** — Handles sandboxed file access, import, library scanning, and file organization
- **MIDIMetadataExtractor** — Extracts song metadata, per-track info, and channel-instrument mappings from MIDI files
- **MIDINoteExtractor** — Builds time-indexed note sequences for the visualization engine

## Planned

- Tempo adjustment during playback
- MIDI output to external devices
- Waveform/spectrogram visualization mode
- Smart playlists (auto-filtered by metadata criteria)
- Batch metadata editing
- MIDI file export with muted tracks stripped
- SoundFont / SF2 bank selection
- Keyboard input for live play-along
