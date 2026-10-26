<p align="center">
  <img src="mac/docs/images/logo.svg" width="128" height="128" alt="Bilge logo">
</p>

<h1 align="center">Bilge</h1>

<p align="center">
  A voice assistant that speaks Turkish and English, for the Mac, Windows and Linux.
</p>

<p align="center">
  <a href="https://github.com/coderssociety/bilge/releases/latest"><img src="https://img.shields.io/github/v/release/coderssociety/bilge?label=Download&style=for-the-badge&color=2A2E7A" alt="Download Bilge"></a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License: GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-27%2B-black?logo=apple" alt="macOS 27+">
  <img src="https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows" alt="Windows 10/11">
  <img src="https://img.shields.io/badge/Linux-AppImage-FCC624?logo=linux&logoColor=black" alt="Linux AppImage">
</p>

<p align="center">
  <b>English</b> · <a href="README.tr.md">Türkçe</a>
</p>

<p align="center">
  <img src="mac/docs/images/en/hud-confirm.png" width="760" alt="Bilge asks before adding an event to the calendar">
</p>

Say “Bilge”, ask for something, and it does it on your computer and answers out loud: your calendar, mail,
messages, files, documents, music, the browser and your smart home. Anything that can't be undone waits for a
spoken yes.

## Download

Every release has all three, under [Releases](https://github.com/coderssociety/bilge/releases/latest):

| System | File | Needs |
|---|---|---|
| **Mac** | `Bilge-<version>.dmg` | macOS 27 or later on Apple silicon, with Apple Intelligence on |
| **Windows** | `Bilge-Setup-<version>.exe` | Windows 10 or 11, 64-bit; installs for your user without administrator rights |
| **Linux** | `Bilge-<version>-x86_64.AppImage`, `Bilge-<version>-aarch64.AppImage` | glibc 2.34+ (Ubuntu 22.04, Debian 12, Fedora 36 or newer); 2.39+ for arm64 |

`SHA256SUMS` lists the checksums. The packages aren't signed yet, so macOS and Windows warn the first time; each
app's page explains how to open it.

## Why Bilge

- **Made for Turkish.** It understands everyday Turkish and knows what a Turkish user asks for: prayer times,
  earthquake alerts from AFAD, Süper Lig, Borsa İstanbul, gold and fuel prices. It speaks English too.
- **Private by default.** Speech recognition, the language model and the voice can all run on your computer. No
  account, no subscription, no recording kept.
- **Your choice of brain.** A model on your computer (MLX on the Mac; Ollama, LM Studio or llama.cpp) or a hosted
  API with your own key (OpenAI, Anthropic, Google Gemini, OpenRouter, Groq, DeepSeek).
- **Safe by design.** Sending, deleting, powering off and locks at home ask first, and text read from a web page or
  an e-mail can never send anything on its own.

## The two apps

The Mac app is built from Apple's own parts (its on-device language model, dictation, MLX); the Windows and Linux
app is the same assistant rebuilt in Python. They follow the same rules and share the Turkish and English command
sets.

| | Mac | Windows and Linux |
|---|---|---|
| Everything it can do, settings, privacy | [mac/README.md](mac/README.md) | [desktop/README.md](desktop/README.md) |
| Source | [`mac/`](mac) (Swift 6, Xcode) | [`desktop/`](desktop) (Python 3.14, uv) |

## Repository layout

| Folder | Contents |
|---|---|
| `mac/` | The Mac app and its tested core package (`mac/Packages/AsistanKit`) |
| `desktop/` | The Windows and Linux app, its tests and installers |
| `bench/` | Speech recognition, routing and end-to-end command sets both apps are measured with |

Releases are built by `.github/workflows/release.yml` from a `v*` tag: the DMG on macOS, the installer on Windows
and the AppImages in Docker, published together as one draft release. Each app's README explains how to build it
from source.

## License

GPL-3.0, see [LICENSE](LICENSE). Each app lists the open-source components and models it uses.
