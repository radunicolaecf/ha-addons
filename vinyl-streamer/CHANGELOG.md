# Changelog

## [2.0.5] - 2026-08-31

### Added
- FLAC

## [2.0.4] - 2026-03-03

### Fixed
- Dynamic channel layout: now correctly uses "mono" when channels=1, "stereo" when channels=2
  (was hardcoded to "stereo" causing FFmpeg warnings and incorrect behavior in mono mode)
- Applied fix to both streaming and recording FFmpeg commands

### Removed
- Removed leftover development backup file (run 2.sh)

---

## [2.0.3] - 2026-02-05

### Fixed
- Set explicit channel layout for FFmpeg to avoid "Guessed Channel Layout" warning

---

## [2.0.2] - 2026-02-05

### Changed
- Moved "Add Repository" button under Installation section in README

---

## [2.0.1] - 2026-02-05

### Changed
- Updated terminology for Home Assistant 2026.2 ("add-on" → "app")
- Updated service names: `hassio.addon_*` → `hassio.app_*`
- Automation examples now in collapsible section

---

## [2.0.0] - 2026-02-05

### Major Release 🎉
Full Home Assistant integration with MQTT Discovery, recording controls, and improved stability.

### Highlights
- **MQTT Discovery**: Sensors and controls auto-created in Home Assistant
- **Recording via MQTT**: Start/stop recording with HA buttons
- **Audio Format Selection**: MP3, AAC, or Opus encoding
- **Compressor Controls**: Threshold and ratio settings
- **Reorganized UI**: Collapsible settings sections

### All Features Since 1.7.7
- MQTT Discovery with auto-detection of Mosquitto broker
- Recording to MP3 or FLAC via MQTT commands
- Audio format selection (MP3/AAC/Opus)
- Volume adjustment (-10 to +10 dB)
- Compressor with threshold (-40 to -5 dB) and ratio (2:1 to 20:1)
- Max listeners and genre tag configuration
- Status file for HA sensors
- XML escape for security
- Exponential backoff on FFmpeg restart
- Port verification before streaming

---

## [1.8.15] - 2026-02-04

### Added
- **Recording feature**: Save audio to MP3 or FLAC files
  - Start/stop recording via MQTT commands or HA buttons
  - Files saved to configurable path (default: /share/vinyl-recordings)
  - MQTT buttons auto-created in HA for easy control
- **Recording status sensor**: Shows when recording is active

### Changed
- FFmpeg restart now uses exponential backoff (5s, 10s, 20s, 40s, max 60s)
- Icecast startup now waits for port 8000 to be ready (more reliable)

### Security
- XML escape for station name, description, and genre (prevents config injection)
- Icecast config file permissions restricted (chmod 600)

## [1.8.14] - 2026-02-04

### Added
- Compressor threshold setting (-40 dB to -5 dB)
- Compressor ratio setting (2:1 to 20:1)

### Changed
- Reorganized settings into collapsible sections:
  - Audio Quality (format, samplerate, channels, bitrate)
  - Audio Processing (volume, compressor)
  - Noise Reduction (highpass, lowpass, denoise)
  - Icecast Settings (max listeners, genre)
  - MQTT Integration (enable, host, credentials)

## [1.8.13] - 2026-02-04

### Added
- MQTT Discovery: Auto-creates sensors in Home Assistant when enabled
  - Binary sensor for streaming status
  - Sensors for format, bitrate, uptime, and stream URL
- Auto-detects Mosquitto app (no manual configuration needed)
- Optional manual MQTT host/username/password for external brokers

## [1.8.12] - 2026-02-04

### Added
- Audio format selection: MP3 (default), AAC, or Opus encoding
- Configurable max listeners (1-100)
- Customizable genre tag for stream metadata
- Status file at /share/vinyl-streamer/status.json for Home Assistant sensors

## [1.8.10] - 2026-02-04

### Changed
- Added -1 dB and +1 dB options to volume control

## [1.8.9] - 2026-02-04

### Changed
- Volume control uses dropdown with -10 to +10 dB in 2 dB steps

## [1.8.8] - 2026-02-04

### Changed
- Volume control now uses dropdown with -10 to +10 dB in 2 dB steps
- Shows actual dB values in UI (e.g. "-6 dB", "+4 dB")

## [1.8.7] - 2026-02-04

### Fixed
- Volume control now uses int(0,40) with offset (HA doesn't support negative int ranges)
- 20 = no change, 0 = -20dB, 40 = +20dB

## [1.8.6] - 2026-02-04

### Added
- Testing: Changed volume_boost to int(-20,20) - testing negative numbers (BROKE)

## [1.8.5] - 2026-02-04

### Added
- Testing: Added volume_boost with int(0,20) - no negative numbers

## [1.8.4] - 2026-02-04

### Added
- Testing: Added only compressor_enabled (bool) to isolate issue

## [1.8.3] - 2026-02-04

### Fixed
- Reverted to exact 1.7.7 config structure (removed volume_db, compressor_enabled)

## [1.8.2] - 2026-02-04

### Fixed
- Moved volume_db and compressor_enabled to root level (HA has limit on nested sections)

## [1.8.1] - 2026-02-04

### Fixed
- Added missing audio_processing translations (may fix app visibility)

## [1.8.0] - 2026-02-04

### Added
- Audio Processing section with volume adjustment and compressor (testing incremental features)

## [1.7.8] - 2026-02-04

### Fixed
- Reverted to 1.7.7 config to restore app visibility (debugging 1.9.x issues)

## [1.9.3] - 2026-02-04

### Fixed
- Removed stereo_width option temporarily to fix app visibility
- Reverted to str type for password and float for denoise_strength (same as working 1.7.7)

## [1.9.2] - 2026-02-04

### Fixed
- Changed numeric list values to text labels (stereo_width, denoise_strength) to fix app visibility

## [1.9.1] - 2026-02-04

### Fixed
- Changed float schema types to list to fix app visibility (stereo_width, denoise_strength)

## [1.9.0] - 2026-02-04

### Added
- **Audio Format Selection**: Choose between MP3, AAC, or Opus encoding
- **Audio Processing Section**:
  - Volume adjustment (-20 to +20 dB)
  - Audio compressor for dynamic range control
  - Stereo width adjustment (mono to extra wide)
- **Icecast Settings Section**:
  - Configurable max listeners (1-100)
  - Custom genre tag
- **Recording Feature**: Save stream to MP3 or FLAC files while streaming
- **Home Assistant Integration**: Status file at /share/vinyl-streamer/status.json for creating HA sensors
- **Docker health check**: Automatic container restart on Icecast failure

### Changed
- FFmpeg restart now uses exponential backoff (5s to 60s) to prevent log spam
- Better Icecast startup verification (waits for port to actually open)
- Improved startup logging with configuration summary
- More robust cleanup on shutdown (graceful + force kill)

### Security
- XML escape for station name, description, and genre (prevents config injection)
- Config file permissions restricted (chmod 600)

## [1.7.7] - 2026-02-04

### Fixed
- Fixed translations for nested fields using "fields" key structure

## [1.7.6] - 2026-02-04

### Fixed
- Fixed translations for nested configuration fields (noise reduction, audio quality) using dot notation

## [1.7.5] - 2026-02-04

### Changed
- Added detailed descriptions for all configuration options explaining what each setting does

## [1.7.4] - 2026-02-04

### Fixed
- Fixed "De-noise" spelling in labels

## [1.7.3] - 2026-02-04

### Fixed
- Simplified noise reduction labels (Highpass, Lowpass, Denoise instead of technical names)

## [1.7.2] - 2026-02-04

### Changed
- Grouped audio settings (samplerate, channels, bitrate) into collapsible "Audio Quality" section

## [1.7.1] - 2026-02-04

### Changed
- Added "(Default)" label to default options in radio buttons for clarity

## [1.7.0] - 2026-02-04

### Changed
- Improved configuration UI with dropdown selects instead of radio buttons
- Added translations for better labels and descriptions
- Password field now hides input

## [1.6.0] - 2026-02-04

### Added
- Low latency mode option to reduce stream delay (~2-3s instead of ~5-10s)
  - Reduces Icecast buffer sizes
  - Adds FFmpeg low-delay flags
  - Disabled by default (may cause stuttering on slow networks)

## [1.5.0] - 2026-02-04

### Added
- Noise reduction options with configurable audio filters:
  - Highpass filter (20-100 Hz) to remove turntable rumble
  - Lowpass filter (10000-20000 Hz) to remove hiss and high-frequency noise
  - FFT-based denoiser with adjustable strength (0.1-1.0)
- All filters are optional and disabled by default

## [1.2.0] - 2026-02-02

### Changed
- Updated FFmpeg command to match user's working configuration
- Default audio device changed to "default" (simpler)
- Added `-sample_fmt s32p` for better audio quality
- Removed `-reservoir 0` option
- Skip device check when using "default" device

## [1.1.0] - 2026-02-02

### Changed
- Replaced Darkice with FFmpeg (more portable, available in Alpine repos)
- Fixed Icecast paths for Alpine Linux
- Added clean shutdown handling

## [1.0.0] - 2026-02-02

### Added
- Initial release
- Bundled Icecast 2 server
- Bundled Darkice encoder
- Configurable station name and mount point
- Configurable audio input device
- Auto-restart on Darkice failure
- Music Assistant compatible MP3 stream
