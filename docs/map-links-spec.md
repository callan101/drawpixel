# Drawing App Update Spec: Tile Types, Links, and Map File Format

**Version:** 1.1
**Goal:** Replace the hue/saturation encoding with (a) exact-hex tile types and (b) explicit links stored beside the image, without breaking the existing PNG workflow.

Changes from 1.0: fits the editor's infinite sparse canvas (§4.1), handles the existing select/move/cut/paste tools (§6.4), Link tool on `K` with links always visible (§5, §6.1), finger input matches the iPad gesture model (§5.5), empty = absent/transparent (§3.2), and tighter rules for IDs, duplicates and the legacy converter.

---

## 1. Scope

### In scope
- Exact-hex tile types attached to palette swatches
- Map file format (`.map.json`): PNG + palette + links
- Link tool (create / delete / inspect)
- Link integrity when tiles are painted, erased, moved, cut or deleted
- Map import/export (clipboard, file, drag-drop)
- One-time converter for legacy hue/saturation maps

### Out of scope (future)
- Layers, free-placed objects, per-tile properties beyond links
- Game-side loader changes (separate repo; contract in §9)

---

## 2. Concepts

| Term | Meaning |
|---|---|
| **Tile type** | What a tile is (`wall`, `button`, `door`). Defined only by the pixel's exact hex color. |
| **Palette** | The editor's swatches. A swatch may carry a tile type and link role. |
| **Linkable type** | A tile type whose `linkRole` is `source`, `target` or `both`. |
| **Link** | A directed connection from a source tile to a target tile. |
| **Map mode** | On whenever at least one swatch has a tile type. Enables unknown-pixel highlighting. |

Rule: **pixel color never encodes links.** All buttons share one color; all doors share one color.

---

## 3. Palette and Tile Types

### 3.1 Format (in the map file)
```json
"palette": [
  { "color": "#555555", "type": "wall" },
  { "color": "#22cc88", "type": "button", "linkRole": "source" },
  { "color": "#3366ff", "type": "door",   "linkRole": "target" }
]
```
- `color`: lowercase `#rrggbb`. Unique.
- `type`: unique, non-empty string used by the game.
- `linkRole` (optional): `"source"`, `"target"` or `"both"`. Absent = not linkable.
- There is **no `empty` entry**: an unpainted cell (transparent in the PNG) is empty.

### 3.2 Behaviour
- Matching is **exact** hex equality. No HSV math.
- Empty: cells with no pixel. On PNG import, alpha < 128 is empty; other alpha is ignored.
- Black is an ordinary color and may be given a type like any other.
- **Editing types:** the color picker for a palette swatch has a *type* field and a *role* selector. Clearing the type removes it from the palette file entry.
- **Editing a typed swatch's color** moves the type to the new hex and recolors every tile of the old hex (one undo step per picker session). If the new hex already belongs to another typed swatch, the edit is refused.
- **Deleting a typed swatch** (drag off the bar) removes the type; its tiles become unknown.
- Two swatches with the same hex share one type entry.
- **Unknown pixels** (painted, color not typed) are only highlighted in map mode: dashed outline plus a count in the status bar ("3 unknown"). Export still works but warns.
- The palette (swatches + types) is autosaved with the drawing and exported in each map file. Importing a map replaces the palette's types with the file's.

---

## 4. Map File Format

### 4.1 Coordinates
The editor canvas is infinite and sparse (negative coordinates are normal). Internally, links use **world coordinates**. On export the map is the bounding box of all painted pixels; `origin` records that box's world position, and every coordinate in the file is **0-based, relative to `origin`** (top-left = `[0, 0]`). On import, the map is placed back at `origin` so a round trip is lossless. The game ignores `origin`.

### 4.2 Structure (`.map.json`)
```json
{
  "format": "tilemap",
  "version": 1,
  "name": "level_03",
  "origin": [-12, 4],
  "width": 64,
  "height": 48,
  "image": "data:image/png;base64,iVBORw0KGgo...",
  "palette": [ ... ],
  "nextLinkId": 4,
  "links": [
    { "id": "l1", "from": [4, 9], "to": [12, 3] },
    { "id": "l2", "from": [7, 2], "to": [12, 3] },
    { "id": "l3", "from": [7, 2], "to": [15, 8], "props": { "mode": "toggle" } }
  ]
}
```

### 4.3 Field rules
- `version`: integer. The loader rejects versions newer than it knows.
- `width`/`height`: must match the decoded image, or loading fails.
- `image`: PNG data URL, one pixel per tile, transparent = empty.
- `links[].id`: unique in the file, `"l" + n`. `nextLinkId` is always greater than every `n` in use. On import, any missing or clashing id is reassigned.
- `links[].from` / `to`: `[x, y]`, 0-based from the top-left of the image.
- `links[].props`: optional object, passed through untouched.

### 4.4 Validation (on load and before export)
A link is **invalid** if:
1. `from` or `to` is outside the image.
2. The tile at `from` isn't a type with `linkRole` `source` or `both`.
3. The tile at `to` isn't a type with `linkRole` `target` or `both`.
4. `from` equals `to`.

Duplicates (same `from` and `to`) are merged on load: the first one is kept; if their `props` differ, a warning is shown.

**Invalid links from a file are kept**, drawn red and dashed, and counted in the status bar with a *Remove invalid* action. They are only removed automatically if one of their tiles is later edited (§6.2). Editing never creates an invalid link.

---

## 5. Link Tool

### 5.1 Entering the mode
- Toolbar button **Link**, shortcut **`K`** (`L` stays the Line tool). Included in Tab cycling and the quick menu.
- In Link mode nothing is painted.

### 5.2 Creating a link
1. Tap a source tile: it gets a ring, and every valid target is outlined.
2. Tap a target: a link is created and the source **stays selected**, so more targets can be tapped.
3. Tap empty space, press `Esc`, or tap the selected source again to deselect.

- Tapping an invalid target flashes it red.
- Tapping another source switches the selection to it. A `both` tile acts as a target if a source is selected, otherwise it becomes the selection.
- An exact duplicate does nothing.

### 5.3 Deleting a link
- Tap a link line to select it: it's drawn thicker, with a **×** button at its midpoint.
- Press **×**, `Delete`, `Backspace` or `X` to delete it.
- With a source selected, a **Clear links** button removes all of its outgoing links.

### 5.4 Inspecting
- Hovering a linkable tile (mouse, or Apple Pencil hover) highlights every link touching it and dims the rest.
- The status bar shows e.g. `button (4,9) → 2 targets` or `door (12,3) ← 3 sources`. Coordinates are relative to the map origin, as in the file.
- The selected source is also inspected, so iPad users without hover get the same information.

### 5.5 Input (iPad and desktop)
- Pencil and mouse taps act on links.
- A **one-finger tap** that doesn't move also acts on links. A one-finger drag still pans, and pinch still zooms; two- and three-finger taps keep undo/redo.
- Hit testing picks the nearest tile center or link line within **22 CSS px** (the 44 px target). When zoomed out far enough that tiles are smaller than that, the nearest one wins.

---

## 6. Link Overlay and Integrity

### 6.1 Overlay
- **Links are always shown** in every tool.
- Each link is drawn from tile center to tile center with an arrowhead at the target, in the same canvas pass as the pixels (after them).
- Color: one per source tile from a rotating set of high-contrast colors. Invalid links are red and dashed.

### 6.2 Editing linked tiles
Every link remembers the color of each endpoint. After any edit (brush, line, eraser, delete, cut, paste, import, swatch recolor), each link whose endpoint color changed is checked:
- If the new tile is still compatible with that end's role, the link is kept.
- Otherwise it's removed.
- If any links were removed, a toast says "Removed N links" with an **Undo** button.

### 6.3 Undo/redo
Undo entries capture pixels **and** links together, so undoing a stroke that removed links restores them. Creating and deleting links are their own undo steps. Editing a swatch's type is a palette undo step.

### 6.4 Select / move / cut / copy / paste
- **Move:** when a selection is lifted into a float, link endpoints inside it move with it, and the overlay follows the float live. Committing keeps them; links are re-checked afterwards.
- **Delete / cut:** endpoints in the removed area are gone, so those links are removed (with the toast).
- **Copy / paste:** links are not copied. Pasted tiles start unlinked.

---

## 7. Import / Export

### 7.1 Export
| Action | Output |
|---|---|
| **Copy map** | `.map.json` text on the clipboard (main path into the game) |
| **Download map** | `<name>.map.json` (iPad: share sheet) |
| **Copy image / Download PNG** | Image only, as today. Warns if the map has links: "Links are not included in a PNG." |

Exporting with unknown pixels or invalid links shows a warning but still exports.

### 7.2 Import
Paste, file picker and drag-drop accept:
1. **`.map.json` text or file**: replaces the drawing, links and tile types (one undo step), placed at `origin`.
2. **Plain PNG**: imported as today, as a movable float with no links.
3. **Legacy hue/sat PNG**: as a plain PNG; if pixels match the legacy rules (§8), the status bar offers **Convert legacy links**.

Detection: text that parses as JSON with `"format": "tilemap"` is a map; image data is a PNG.

### 7.3 Persistence
The drawing is already autosaved to local storage (debounced, in try/catch) and restored on startup. Links, `nextLinkId` and tile types are added to that save. Pixels stay in their compact internal form; the PNG is only built on export.

---

## 8. Legacy Converter

Input: the current canvas, using the old encoding (hue selects the type, saturation selects the pairing).

Config (editable in the converter dialog; defaults shown):
```json
{
  "rules": [
    { "hue": 150, "type": "button" },
    { "hue": 100, "type": "door" }
  ],
  "hueTolerance": 3,
  "saturationTolerance": 2,
  "minSaturation": 10,
  "minBrightness": 10
}
```
- Hue is in degrees (0–360); saturation and brightness are percentages (0–100).
- Every rule's `type` must already exist on a typed swatch (that's where the link role and the exact color come from). Missing types are listed and the conversion is blocked.

Steps (all computed from the original colors before anything is recolored):
1. Convert each pixel to HSV. Skip pixels below `minSaturation` or `minBrightness` (their hue is unreliable). A pixel matches a rule if the **circular** hue distance is ≤ `hueTolerance`.
2. Group matched pixels by saturation: round to a whole percent, sort, and start a new group whenever the gap to the previous value exceeds `saturationTolerance`.
3. In each group, link **every source to every target**.
4. Recolor every matched pixel to its type's exact swatch color.
5. Show a summary first: "Found 4 groups, 9 buttons, 6 doors → 11 links", with warnings for groups that have sources but no targets (or the reverse).
6. Apply as a single undo step.

---

## 9. Game-Side Contract

- Read `palette` into a `hex → type` map and look up each pixel by exact match. Transparent pixels are empty.
- Read `links` as given (0-based image coordinates). No extra rules on the game side.
- For a plain PNG, use a built-in palette and no links.
- Ignore unknown top-level fields (including `origin` and `nextLinkId`) and unknown `props` keys.

---

## 10. Implementation Order

1. Tile types on swatches; unknown-pixel highlight; status bar.
2. Link model in the editor: world coordinates, undo, autosave, always-on overlay.
3. Link tool (create, delete, inspect) and integrity (§6.2–6.4) together, so new links never break silently.
4. Map export/import.
5. Legacy converter.
6. Game loader (separate repo), then remove the hue/sat code there.

---

## 11. Acceptance Checklist

- [ ] Eyedropper sample → paint → re-sample gives an identical hex.
- [ ] One button links to 3 doors and 2 buttons link to 1 door, using touch only on iPad.
- [ ] Painting a linked door with wall removes its links, shows a toast, and Undo restores tile and links.
- [ ] Moving a selection containing a linked button moves its links; Undo puts them back.
- [ ] Copy map → paste into a fresh editor → identical pixels, positions and links.
- [ ] Copy map → paste into game → buttons open the correct doors.
- [ ] Plain PNG paste still works in both editor and game.
- [ ] A legacy map converts with the same pairings as before, and the summary matches a hand count.
- [ ] Reloading the page restores the drawing, types and links.
