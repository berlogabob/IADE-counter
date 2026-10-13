# 03 QR share: host shows a QR for the viewer link

Step 2 works (host pushes, viewer mirrors, clocks synced). `qr_flutter` is already in pubspec.yaml.
Smallest possible change, only `lib/main.dart`.

## Do
1. Host only (`widget.sync != null && !widget.viewer`): add an `IconButton`/`TextButton.icon` (icon `Icons.qr_code`, label "Viewer link") to the button `Wrap` at the bottom of `build`, visible in both idle and running states.
2. On press, `showDialog` with an `AlertDialog` containing a `QrImageView` (from `package:qr_flutter/qr_flutter.dart`, white background, `size: 260`) of the viewer URL, the URL as selectable text under it, and two actions: "Copy link" (use the existing `_copy`) and "Close".
3. Viewer URL = `Uri.base.replace(fragment: '/view/${widget.sync!.token}').toString()`. `Sync.token` is already a public final field.
4. No other file changes. Do not touch `lib/sync.dart`, `lib/session.dart`, `lib/phase.dart`, tests, or pubspec.

## Acceptance
`flutter analyze` and `flutter test` pass.

## Known gap (not for you to fix)
The viewer link reuses the host's edit token, so anyone with it can write. Separate read-only tokens come with the admin screen (step 7).
