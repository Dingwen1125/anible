# Anible Desktop Pet

A tiny native macOS desktop pet prototype built with Swift and AppKit.

The first version creates a transparent floating pet window that:

- stays above normal desktop windows
- walks along the bottom of the visible screen
- randomly sits, sleeps, or gets excited
- can be clicked for a reaction
- can be dragged around

## Run

```bash
swift run AniblePet
```

The app runs as an accessory app, so it does not show a normal Dock icon.

## Next Steps

- Replace the drawn placeholder pet with sprite-sheet animations.
- Add window-edge awareness with Accessibility and CoreGraphics APIs.
- Add multi-screen support.
- Add a behavior event channel for camera-driven animal recognition.
