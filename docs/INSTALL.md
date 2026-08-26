# Install, Update, and Uninstall

## Requirements

- macOS 14 or later
- ABC and 2-Set Korean input sources enabled in macOS

## Install

1. Download `HanKey-<version>.dmg` and `SHA256SUMS.txt` from the same GitHub Release.
2. Verify the checksum:

   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```

3. Open the DMG and drag `HanKey.app` to Applications.
4. Launch HanKey from Applications. The app is Developer ID signed and Apple notarized; do not bypass a Gatekeeper warning for an artifact that fails verification.
5. Read the first-run privacy explanation, then grant Input Monitoring and Accessibility only if you want global automatic correction.
6. Optional: enable “로그인 시 한글변환 실행” in General settings. If macOS requires approval, use the adjacent button to open Login Items settings.

## Update

v1 has no network updater. Quit HanKey, download and verify the newer notarized DMG, then replace `HanKey.app` in Applications. Local rules remain in Application Support. A signature or bundle change may require macOS to ask for permissions again.

## Uninstall

1. Quit HanKey from its menu bar menu.
2. If enabled, turn off “로그인 시 한글변환 실행” before deleting the app.
3. Move `/Applications/HanKey.app` to Trash.
4. Optional local-data removal:

   ```sh
   rm -rf "$HOME/Library/Application Support/HanKey"
   defaults delete com.dindbdong.hankey
   ```

5. Optional permission cleanup: remove HanKey from System Settings → Privacy & Security → Input Monitoring and Accessibility.

The optional commands permanently remove local rules and settings. Export rules first if you may need them later.
