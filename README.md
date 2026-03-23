# MarkdownViewer

Small native macOS Markdown viewer built with SwiftUI and AppKit.

## Features

- Open a local Markdown file
- Render it read-only in a fast native window
- No editing, syncing, or project management

## Run

```bash
swift run
```

From the app, use `Open Markdown` or `Cmd+O` to load a file.

## Distribution Build

Create a universal macOS `.app` bundle and ZIP archive:

```bash
./scripts/build-distribution.sh
```

Optional environment variables:

- `MARKDOWN_VIEWER_BUNDLE_ID=com.yourcompany.MarkdownViewer`
- `MARKDOWN_VIEWER_VERSION=1.0.0`
- `MARKDOWN_VIEWER_BUILD_NUMBER=1`
- `MARKDOWN_VIEWER_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"`

Without `MARKDOWN_VIEWER_SIGN_IDENTITY`, the script ad-hoc signs the app. Output artifacts are written to `dist/`.

If `Resources/AppIcon.icns` exists, the distribution build embeds it as the app icon.
