# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project context

This repo is `megalomon/Pixelorama_owl`, a fork of [Orama-Interactive/Pixelorama](https://github.com/Orama-Interactive/Pixelorama): an open-source pixel art editor written in GDScript on **Godot 4.7** (CI builds with Godot **4.7.2**, see `config/features` in `project.godot`). Work happens directly on `master` of the fork.

Upstream's `CONTRIBUTING.md` does **not allow** AI-assisted contributions. Never open PRs or post comments against the upstream repository.

The fork is customized for the user's own Android devices, listed in `devices_specs.md`. Android is the **only** target: `export_presets.cfg` contains just the `Android` preset, and desktop, web and installer tooling has been removed. Optimizations for these devices may freely sacrifice portability to other platforms.

## Commands

There is no automated test suite. CI (`.github/workflows/static-checks.yml`) runs static checks only, and every change must pass them:

```bash
pip install gdtoolkit          # provides gdformat + gdlint (CI uses Scony/godot-gdscript-toolkit@master)
gdformat --diff .              # formatting check (drop --diff to apply)
gdformat path/to/File.gd       # format a single file
gdlint .                       # lint; rules configured in .gdlintrc (max-file-lines 2000, some rules disabled)
codespell --skip "./addons,./Translations,./src/UI/Dialogs/AboutDialog.gd,./src/Classes/SoftwareParsers/PhotoshopParser.gd" -L chello,doubleclick,Manuel,SectionIn
```

The APK is built by `.github/workflows/android.yml` on every push to `master` (and via manual dispatch); the signed APK is uploaded as the `Pixelorama-Android` workflow artifact and published as a GitHub release (tag `android-<run number>`), so the newest build is always at `https://github.com/megalomon/Pixelorama_owl/releases/latest/download/Pixelorama.apk`. It runs in the `barichello/godot-ci:4.7.2` image and uses a Gradle build (`gradle_build/use_gradle_build=true`, required by the `applinks` Android plugin). Key points:

- The SDK packages installed in the workflow (`ANDROID_PLATFORM`, `ANDROID_BUILD_TOOLS`, `ANDROID_NDK`) must match `platform/android/java/app/config.gradle` of the Godot version in use. Update them when bumping Godot.
- Release signing uses the repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_ALIAS` and `ANDROID_KEYSTORE_PASSWORD`, passed to Godot via the `GODOT_ANDROID_KEYSTORE_RELEASE_*` env vars. Never change the keystore: Android only installs updates signed with the same key.
- `version/code` in the preset is overwritten with the workflow run number so every build installs as an update.
- `android/` (the Gradle build template) is gitignored and installed at build time with `--install-android-build-template`.

The APK itself is only built by the workflow.

### Validating changes without a device

Godot 4.7.2 can be downloaded into the container (`Godot_v4.7.2-stable_linux.x86_64.zip` from the `godotengine/godot-builds` releases) to check changes headlessly. Run `--headless --import` twice (the first run only builds the class cache), then `--headless --quit-after 300` to boot the app. To exercise specific features, add a temporary autoload through an untracked `override.cfg` in the project root (it is gitignored), e.g. `[autoload]` with `Tester="*res://_tmp/tester.gd"`, that awaits `Global.pixelorama_opened` and drives the UI. Compare the output against the same run on the previous commit; 4 `custom_samplers` shader errors are pre-existing. Delete the temporary files afterwards.

## Removed upstream features

Code that can never run on Android was removed. Don't reintroduce it:

- Web/HTML5 (`HTML5FileExchange`, `JavaScriptBridge` downloads, the HTML5 save dialog), Steam achievements, the desktop command-line interface and browser drag-and-drop image downloads.
- macOS/Windows/Linux-only branches (Cmd key, Windows tablet driver, XDG data dirs, window position/size restore, Flatpak hints) and the desktop-only preferences (single-window mode, window transparency/opacity, dummy audio driver, `override.cfg` writing).
- FFmpeg: video export/import and the Recorder's GIF export. The Recorder only captures the canvas (screen capture via `DisplayServer.screen_get_image` is not implemented on Android).
- EXR and the video formats remain in `Export.FileFormat` only to keep the enum values stable (they are stored in `.pxo` files and used by extensions), but are not offered.

Android-specific behavior is now unconditional, e.g. export paths use the SAF `directory#file` form and `.pxo` files are written in place without a temporary file.

## Code conventions

- Use static typing everywhere (`var x := ...`, typed arrays and dictionaries, return types). Follow the GDScript style guide that `gdformat` enforces.
- Every script and resource has a `.uid` sidecar file, and scenes/autoloads may reference `uid://...`. Keep the sidecar when moving or renaming a file.
- Godot rewrites `.tscn` files (especially `src/Main.tscn`) on its own. Don't commit scene changes you didn't intend. Edit a `PackedScene` UI element in its own scene, not in a parent scene.
- Put user-facing strings through `tr()`. Add new strings to `Translations/Translations.pot` only and never edit the `*.po` files, which Crowdin manages.
- Reuse the existing `ErrorDialog` instead of creating new error dialogs.
- Set new interactive buttons to the pointing-hand cursor.
- `addons/` contains vendored third-party code, some of it locally patched. `addons/README.md` lists the upstream commits and local modifications. Update that file whenever you change an addon.

## Architecture

### Autoload singletons (`src/Autoload/`, registered in `project.godot`)

- **`Global`** is the central hub. It holds `projects` / `current_project`, references to the main UI nodes (`Global.canvas`, `Global.animation_timeline`, `Global.control`, …), user preferences, and app-wide signals (`project_switched`, `cel_switched`, `project_data_changed`, …). It also registers all keyboard shortcuts in `_initialize_keychain()` through the `Keychain` addon.
- **`Tools`** holds the registry of tools (`Tools.tools: Dictionary[String, Tool]`, each pointing to a `.tscn` under `src/Tools/`). It also manages the left/right mouse-button tool slots and the colors assigned to each button, routes canvas input to the active tool (`handle_draw`), and handles mirroring and snapping.
- **`OpenSave`** handles `.pxo` load/save. A `.pxo` file is a ZIP that contains `data.json` (from `Project.serialize()`) plus raw image data under `image_data/frames/<frame>/layer_<n>`, along with brushes, reference images and tile maps.
- **`Import`**, **`Export`**, **`Palettes`**, **`Themes`**, **`DrawingAlgos`** (shared pixel algorithms) and **`HTML5FileExchange`** (web builds).
- **`ExtensionsApi`** is the public API for user extensions. It is split into sub-APIs: `general`, `menu`, `dialog`, `panel`, `theme`, `tools`, `selection`, `project`, `export`, `import`, `palette` and `signals`. Extension loading and compatibility checks live in `src/HandleExtensions.gd`, where the API version comes from `config/ExtensionsAPI_Version` in `project.godot`. Changing public behavior here can break third-party extensions.

### Document model (`src/Classes/`)

- `Project` holds `frames: Array[Frame]`, `layers: Array[BaseLayer]`, `current_frame` / `current_layer`, `selected_cels` (a list of `[frame, layer]` pairs), `selection_map`, `tilesets`, and its own `undo_redo: UndoRedo`.
- A **cel** is the content at a frame×layer intersection, accessed as `project.frames[frame_index].cels[layer_index]`. Each layer type in `Classes/Layers/` has a matching cel type in `Classes/Cels/`: Pixel, Group, 3D, TileMap and Audio. `Global.LayerTypes` enumerates the types. Tools are filtered by layer type (`Tool.layer_types`).
- `ImageExtended` wraps `Image` and adds indexed-color mode. Pixel cel images are `ImageExtended`.
- Image effects (`src/UI/Dialogs/ImageEffects/`) extend `ImageEffect` and are often backed by shaders in `src/Shaders/Effects/` via `ShaderImageEffect`.

### Undo/redo pattern

Every project mutation goes through `project.undo_redo`. Image edits don't store full images. The pattern is:

1. Snapshot the cel data before the edit (`_get_undo_data()` / `project.serialize_cel_undo_data`).
2. Apply the edit and snapshot again.
3. `create_action(name)`, then `project.deserialize_cel_undo_data(redo, undo)` registers compressed image data via `Global.undo_redo_compress_images`.
4. Add `Global.undo_or_redo.bind(false/true, frame_index, layer_index)` as the do/undo methods, then `commit_action()`.

`Global.undo_or_redo` refreshes textures, the canvas and the previews. It only does this for a fixed list of action names (`"Draw"`, `"Select"`, `"Scale"`, …). A new action name that needs a texture refresh must either be added to that list or refresh the textures itself. `src/Tools/BaseDraw.gd` (`prepare_undo` / `commit_undo`) is the reference implementation.

### Tools (`src/Tools/`)

Every tool is a scene plus a script extending `BaseTool`. Intermediate bases are `BaseDraw` (brush-based drawing), `BaseShapeDrawer` and `BaseSelectionTool`. Tools implement `draw_start` / `draw_move` / `draw_end`, `draw_indicator` and `draw_preview`. Options persist via `get_config` / `set_config`. To add a tool:

1. Create its scene under the matching subfolder (`DesignTools`, `SelectionTools`, `UtilityTools` or `3DTools`).
2. Register it in `Tools.tools`.
3. Add icons at `assets/graphics/tools/<name>.png` and `assets/graphics/tools/cursors/<name>.png`.
4. Add a shortcut action in `Global._initialize_keychain()`.

### UI (`src/UI/`)

`src/Main.tscn` / `Main.gd` is the entry point; it also handles command-line arguments and backups. `UI.tscn` uses the `dockable_container` addon for the rearrangeable panel layout. The canvas (`UI/Canvas/`) is a stack of drawer nodes: grid, pixel grid, onion skinning, selection, previews, indicators, measurements and so on. The timeline lives in `UI/Timeline/`, and the top menus in `UI/TopMenuContainer/`.
