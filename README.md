# PNG Compressor + PDF Vector Check

Small macOS SwiftUI app for two desktop workflows:

- Lossless PNG optimization by re-encoding the image and stripping metadata.
- PDF inspection that checks whether page content streams contain vector or text drawing commands.

## Run

Open the package in Xcode and run the macOS target, or build from Terminal:

```bash
swift build
```

## Notes

- PNG optimization is intentionally conservative in this first version. It only writes a new file if the re-encoded PNG is smaller than the original.
- Optimized files are written next to the original using the `-optimized.png` suffix.
- PDF detection treats text drawing as vector-style content because it is stored as drawing instructions rather than a flat raster image.
