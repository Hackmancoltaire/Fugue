# Fugue

A macOS MIDI player and library manager built with SwiftUI. Fugue lets you import, organize, and play MIDI files with real-time piano roll visualization and per-track instrument control.

## Features

### Library
- **Import & Organize** — Import MIDI files (move or copy), with duplicate detection and automatic artist/album folder structure
- **Browse by Artist/Album** — Sidebar categories with a secondary browse panel for filtering by artist or album
- **Genre Filtering** — Browse songs grouped by genre
- **Search & Sort** — Full-text search across title/artist/album; sort by any visible column with ascending/descending toggle
- **Favorites** — Star songs as favorites; filter library to favorites-only via toolbar or sidebar
- **Column Visibility** — Show/hide columns (genre, duration, tempo, tracks, play count, date added, last played) from the toolbar filter menu
- **Filter Menu** — Toolbar menu combining filter mode, sort column, and column visibility in one place
- **Play Count & Last Played** — Automatically tracked per song

### Playlists
- Create and manage custom playlists with drag-and-drop reordering
- Drag songs from the library onto playlists in the sidebar
- Drop MIDI files directly onto playlists to import and add

### Playback
- Full transport controls — play, pause, stop, seek
- Spacebar play/pause from any window (library, visualizer, settings)
- Spacebar on a non-playing track starts that track
- Repeat modes — off, repeat once, repeat continuously
- Note chasing on resume — re-triggers notes that should be sounding at the current position
- Silent scrubbing — visual-only playhead movement while dragging

### MIDI Output
- Route playback to external MIDI devices
- Select output destination in Settings
- Real-time re-routing without stopping playback

### Visualization
- **Piano Roll** — Scrolling note display colored by MIDI channel
- **Keyboard View** — Keys light up in real time as notes play
- Inline visualization panel with adjustable height, or separate detachable window

### Detail Panel
- Edit title, artist, album, and genre inline
- Favorite toggle
- Full metadata grid — duration, tempo, time signature, track count, format, PPQN, file size, filename, play count, last played, dates
- Instrument and system channel listing with per-track mute/unmute buttons
- Async track info loading — metadata appears instantly, track details load in background

### Context Menu
- Play, Favorite/Unfavorite, Show in Finder, Delete

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI + NSTableView (for smooth scrolling) |
| Data | SwiftData |
| Audio | AudioToolbox (MusicPlayer / MusicSequence) |
| MIDI Parsing | MIDIKitSMF |
| MIDI Output | CoreMIDI |
| Platform | macOS |

## Architecture

- **PlaybackService** — MusicPlayer/MusicSequence lifecycle, playback state, position tracking, note chasing, real-time track muting, external MIDI routing
- **LibraryManager** — Sandboxed file access, import with duplicate detection, library scanning, file organization by artist/album
- **MIDIOutputService** — CoreMIDI client for routing playback to external MIDI devices
- **MIDIMetadataExtractor** — Extracts song metadata, per-track info, and channel-instrument mappings from MIDI files
- **MIDINoteExtractor** — Builds time-indexed note sequences for the visualization engine
- **NativeSongTableView** — NSTableView-backed song list bypassing SwiftUI per-cell overhead for smooth scrolling with thousands of songs

## Planned

- Tempo adjustment during playback
- Waveform/spectrogram visualization mode
- Smart playlists (auto-filtered by metadata criteria)
- Batch metadata editing
- MIDI file export with muted tracks stripped
- SoundFont / SF2 bank selection
- Keyboard input for live play-along
