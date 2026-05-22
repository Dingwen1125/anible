# Anible Desktop Pet

A native macOS desktop pet prototype built with Swift and AppKit.

Anible shows a small floating pet on the main desktop. The pet can idle, walk a short distance, jump onto nearby window title areas, fall back to the Dock area, sleep, and react when dragged.

## Run

```bash
swift run AniblePet
```

## Package As A macOS App

To build a normal double-clickable macOS app bundle:

```bash
./scripts/package_app.sh
```

The packaged app is written to:

```text
dist/Anible Pet.app
```

You can open it with:

```bash
open "dist/Anible Pet.app"
```

The app is locally ad-hoc signed for development/testing. For public distribution outside your own Macs, use a Developer ID certificate and Apple notarization.

## Features

- Floating transparent desktop pet window.
- Main pet management window for switching pets.
- Default hand-drawn pet included.
- Upload custom pet portraits state by state.
- Name uploaded pets.
- Switch between uploaded pets and the default pet.
- Delete uploaded pets from the manager window.
- Right-click the pet to reopen the manager window after closing it.
- Uploaded pets are saved locally across app launches.

## Custom Pet Images

When uploading a custom pet, the app guides you through each state. You do not need to name files manually. The app asks for images in this order:

- Idle: 1 image
- Walking: 4 images
- Jumping: 3 images
- Falling: 2 images
- Held / dragged: 2 images
- Sleeping: 2 images

Transparent PNG or WebP images are recommended. The suggested size is `296x264`.
Prepare custom images facing right by default. The app mirrors the image automatically when the pet faces left, including walking in the opposite direction.

## Local Storage

Uploaded pet images are saved in the current macOS user's Application Support folder:

```text
~/Library/Application Support/AniblePet/
  profiles.json
  Pets/
    <pet-id>/
      idle_01.png
      walking_01.png
      ...
```

This path is outside the project repository, so uploaded pet images are not committed or pushed to GitHub. It also works when the app is packaged and launched as a `.app`.

## Project Structure

- `Sources/AniblePet/main.swift`: app entry point and app delegate.
- `Sources/AniblePet/PetManagerWindowController.swift`: pet manager window.
- `Sources/AniblePet/PetWindowController.swift`: desktop pet behavior, movement, jumping, falling, and window interactions.
- `Sources/AniblePet/PetPortraits.swift`: pet states, upload flow, image requirements, and local storage.
- `Sources/AniblePet/PetView.swift`: default pet drawing, uploaded image rendering, and mouse handling.

## Notes

The pet stays on the normal desktop. It does not follow other apps into full-screen Spaces. If the manager window is closed, right-click the pet and choose `打开宠物管理` to show it again.
