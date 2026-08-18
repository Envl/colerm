# Colerm

Colerm is a native macOS workspace for keeping terminal sessions, projects,
and running processes visible in one calm horizontal workspace.
<video src="https://github.com/user-attachments/assets/a0629699-49ab-42cd-8ef3-6bee47f84bfd" controls width="100%"></video>

[Live website](https://colerm.com) · [GitHub](https://github.com/Envl/colerm) · [X](https://x.com/sesampicr) · [Buy me a coffee](https://buymeacoffee.com/envl)

[Download Colerm for macOS](https://github.com/Envl/colerm/releases/latest/download/Colerm.dmg)

> Colerm is early-stage software. Expect sharp edges while the native app and
> the interactive website demo continue to evolve.

## Highlights

- AppKit-first terminal surfaces backed by Ghostty.
- Resizable horizontal terminal columns with persistent session metadata.
- Drag-to-reorder tabs and `⌘1` through `⌘9` terminal selection.
- Command palette search for open terminals.
- Light and dark system appearance support, including terminal palettes.
- Interactive website demo with multiple virtual workspaces and terminals.

## Repository layout

```text
Sources/ColermApp/       Native macOS app
Tests/ColermAppTests/    Swift tests
Resources/               App resources and Ghostty shell integration
Design/AppIcon/          Source artwork for the app icon
website/                 Svelte website and Workers deployment
Vendor/ghostty/          Pinned upstream source submodule
```

The native app keeps terminal surfaces and paging in AppKit. SwiftUI is used
for surrounding controls and settings. Ghostty C types and ABI-sensitive code
are isolated in `Sources/ColermApp/GhosttyBridge`.

## Requirements

- macOS 14 or newer.
- Swift 6 toolchain and Xcode Command Line Tools.
- Node.js and pnpm for the website.
- Zig only when validating the optional vendored Ghostty source build.

## Native development

```bash
git clone --recurse-submodules https://github.com/Envl/colerm.git
cd colerm

# For an existing clone:
git submodule update --init --recursive

swift build
swift test
./scripts/check.sh
./scripts/run.sh
```

`./scripts/run.sh` builds and launches a relocated debug app bundle. To
regenerate the macOS icon resources:

```bash
./scripts/prepare_app_icon.sh
```

Persisted sessions store reconstructable state such as working directories;
relaunching creates new shell processes in those directories rather than
restoring live processes.

## Releases

Push a protected `v*` tag to build, sign, notarize, and publish the universal
DMG and Sparkle update through GitHub Actions:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow publishes the stable `Colerm.dmg`, a versioned signed app
archive, and `appcast.xml`. The website can always link to the latest DMG, and
installed release builds use the latest appcast for in-app updates. Configure
the `release` GitHub Environment with these secrets before publishing:

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `SPARKLE_ED_PRIVATE_KEY`

The Sparkle public key is checked into `Resources/SparklePublicKey`; its private
counterpart exists only in the GitHub Actions secret and the release operator's
Keychain. Debug builds embed Sparkle for link compatibility but do not start the
production updater or expose its menu command.

Release builds check the appcast in the background and download signed updates
without opening Sparkle's update window. The titlebar update button appears
after the update is staged and immediately installs it before relaunching Colerm.

Updater archives and the appcast are published when the repository Actions
variable `SPARKLE_UPDATES_ENABLED` is `true`. Leave it disabled for the initial
release, then enable it before publishing the first newer version.

## Website development

```bash
cd website
pnpm install
pnpm dev
```

The local demo runs at [http://127.0.0.1:3990/#demo](http://127.0.0.1:3990/#demo).
It uses `@wterm/dom` and `@wterm/just-bash` to provide interactive virtual
terminals without exposing the host shell.

Validate the website before opening a pull request:

```bash
pnpm check
pnpm build
```

## Deploying the website

The website is deployed as a Cloudflare Worker serving Vite's static assets.
The production custom domain is [colerm.com](https://colerm.com), configured
in `website/wrangler.jsonc`.

```bash
cd website
pnpm run deploy:dry-run
pnpm run deploy
```

Deployment requires an authenticated Wrangler session with access to the
Cloudflare zone for `colerm.com`.

## Contributing

1. Create a focused branch.
2. Keep native terminal work AppKit-first and preserve the Ghostty bridge
   boundary.
3. Run `./scripts/check.sh` and the website checks relevant to your change.
4. Open a pull request with a short description and verification notes.

Please do not commit credentials, local `.dev.vars` files, build output, or
machine-specific app state.

## License

Colerm source code is available under the MIT License; see [LICENSE](LICENSE).
The vendored Ghostty source and the `GhosttyTerminal` dependency retain their
own upstream license terms; see `Vendor/ghostty/LICENSE`.
