Colerm app-owned resources live here. `AppIcon.appiconset` contains the
source-size macOS icon family, while `Colerm.icns` is the runtime icon copied
into the built app bundle. Ghostty shell-integration and terminfo resources are
packaged via `GhosttyKit_GhosttyTerminal.bundle` from `libghostty-spm` during
app bundling (falling back to the pinned `Vendor/ghostty` submodule if needed).
