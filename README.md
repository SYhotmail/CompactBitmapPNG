# CompactBitmapPNG

Small macOS SwiftUI app for two desktop workflows:

- Lossless PNG optimization by re-encoding the image and stripping metadata.
- PDF inspection that checks whether page content streams contain vector or text drawing commands.

## Run

Open `CompactBitmapPNG.xcodeproj` in Xcode and run the macOS target, or build from Terminal:

```bash
xcodebuild -project CompactBitmapPNG.xcodeproj -scheme CompactBitmapPNG -configuration Debug build
```

If `project.yml` changes, regenerate the project first with `xcodegen generate`.

## Notes

- PNG optimization is intentionally conservative in this first version. It only writes a new file if the re-encoded PNG is smaller than the original.
- By default, optimized PNGs overwrite the original file; disabling "Overwrite original files" writes them alongside the original using the `-optimized.png` suffix instead.
- PDF detection treats text drawing as vector-style content because it is stored as drawing instructions rather than a flat raster image.
- The app is localized in English, Russian, and Belarusian, following the system's preferred language.
