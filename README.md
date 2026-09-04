# DoveHarper iOS App

A native iOS app for managing the DoveHarperAuthor.com website. Built with SwiftUI and SwiftData for iOS 17+.

## Features

- **Book Management**: Create, edit, and delete books on the live site
- **Publishing**: Push manuscripts, covers, and metadata to GitHub
- **EPUB/PDF**: Automatic sample generation via GitHub Actions
- **Queue System**: Schedule weekly releases with "Fire Now" button
- **Live Links**: Tap to open any book's live page in Safari
- **Text Autocorrect**: Auto-correct "explicit content" → "Explicit Content"
- **Offline Drafts**: Save drafts locally before publishing

## Requirements

- iOS 17.0+
- Xcode 15.4+
- GitHub Personal Access Token
- Shopify Access Token (optional, for paid books)

## Installation

### Option 1: Download IPA (Recommended)

1. Go to [Releases](../../releases)
2. Download the latest `DoveHarper.ipa`
3. Transfer to your iPhone (AirDrop, iCloud, etc.)
4. Open with LiveContainer
5. Trust the developer profile in Settings > General > VPN & Device Management

### Option 2: Build from Source

1. Clone this repository
2. Open `DoveHarper.xcodeproj` in Xcode
3. Select your Apple ID in Signing & Capabilities
4. Build and run on your device

## Configuration

1. Open the app
2. Go to Settings tab
3. Enter your GitHub PAT (needs `repo` scope)
4. Enter your Shopify credentials (optional)
5. Tap Save

## Usage

### Publishing a Book

1. Tap "+" on the Books tab
2. Enter title, tropes, themes, description
3. Select a cover image
4. Import a manuscript (share sheet or file picker)
5. Tap "Publish"
6. Wait for GitHub Actions to generate samples (~1-2 min)
7. Tap "Open Live Page" to view

### Managing Queue

1. Go to Queue tab
2. Tap "+" to add a scheduled release
3. Select a draft book and set a date
4. When ready, tap "Fire All Due Now"

### Editing Published Books

1. Tap a book in the Published section
2. Tap "Edit Book"
3. Make changes
4. Tap "Save" to push updates

## Architecture

```
DoveHarper/
├── Models/           # SwiftData entities
├── Services/         # GitHub, Shopify, Conversion APIs
├── Views/            # SwiftUI screens
├── DoveHarperApp.swift
└── Info.plist
```

## License

Private - Dove Harper only.
