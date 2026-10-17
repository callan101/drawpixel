# Migrating the game from hue/saturation PNG maps to `.map.json`

This guide moves the game off the old encoding, where hue picks the tile type and saturation pairs tiles. In the new format, tile types are exact colours and pairings are explicit links stored beside the image. The full file format is in [map-links-spec.md](map-links-spec.md); this guide covers what the game and the existing maps need.

## 1. Tile types in the new system

Every tile type gets **one exact colour**. Paired mechanics get a **link role**: links always run *source → target*.

| Type id | Old rule | New exact colour | Link role |
|---|---|---|---|
| `spawn` | `#ffffff` | `#ffffff` | — |
| `wall` | `#000000` | `#000000` | — |
| `ladder` | `#8f6945` | `#8f6945` | — |
| `jump_through` | `#b4a968` | `#b4a968` | — |
| `spikes` | `#004bff` | `#004bff` | — |
| `teleporter` | hue 299 | `#fb00ff` | source |
| `teleporter_target` | hue 290 | `#d500ff` | target |
| `knob` | hue 312 | `#ff00cc` | source |
| `mirror` | hue 158 | `#00ffa2` | target |
| `solar_panel` | hue 264 | `#6600ff` | source |
| `door` | hue 114 | `#1aff00` | target |
| `laser` | hue 0 | `#ff0000` | source |
| `laser_aim` | hue 20 | `#ff5500` | target |
| `rope_pivot` | hue 118 | `#08ff00` | source (see open question) |
| `rope_grab` | hue 120 | `#00ff00` | target (see open question) |

Empty cells are **transparent** in the PNG; there is no colour for "empty".

The new colours for the hue-based types are just that hue at full saturation and brightness. The exact values don't matter, but every colour in the table must be different, and they must match the editor's swatches exactly.

**Link direction:** the thing that *does* something links to the thing it *affects*: knob → mirror, solar panel → door, laser → aim, teleporter → teleporter target. One source can link to many targets, and one target can have many sources.

### Open question: rope swings

The old rules don't say that rope pivots and grabs pair through saturation. If each grab belongs to a specific pivot, keep the `source`/`target` roles above and link them. If the game finds the grab by geometry (for example, the grab is directly below its pivot), give both **no** link role, drop them from the converter rules in step 4, and leave the game logic as it is.

## 2. Game loader changes

### 2.1 Detect the input

- **Text that parses as JSON with `"format": "tilemap"`:** a new map (follow 2.2).
- **PNG:** keep the old loader for now, so unconverted maps still work during the switch. Remove it in step 5.

### 2.2 Load a `.map.json`

1. **Check the version.** Reject the file if `version > 1`.
2. **Decode the image.** Decode `image` (a PNG data URL) and check that it is `width × height` pixels; reject the file if not.
3. **Build the colour lookup.** Build `hex → { type, linkRole }` from `palette`, matching **exactly** on lowercase `#rrggbb`.
4. **Read every pixel:**
   - alpha < 128 → empty
   - colour found in the lookup → that tile type
   - anything else → unknown: treat it as empty and log a warning with the coordinates
5. **Read `links`.** Each link is `{ id, from: [x, y], to: [x, y], props? }`. Coordinates are **0-based pixel positions in the image, origin top-left**. Ignore `origin` and `nextLinkId`; they're editor-only. Ignore any unknown fields and unknown `props` keys.
6. **Wire the links.** Look up the tile type at both ends and connect them by type pair:

   | `from` type | `to` type | Game hookup |
   |---|---|---|
   | `teleporter` | `teleporter_target` | teleporter sends the player to that target |
   | `knob` | `mirror` | knob rotates that mirror |
   | `solar_panel` | `door` | powered panel opens that door |
   | `laser` | `laser_aim` | laser fires toward that aim point |
   | `rope_pivot` | `rope_grab` | grab hangs from that pivot (if kept, see the open question) |

   Skip, with a warning, any link whose ends aren't one of these pairs. The editor flags those as invalid, but the game shouldn't crash on them.
7. **Delete the hue/saturation code.** Nothing in this path should compute hue or saturation.

### 2.3 Behaviour to define

The old saturation groups paired *every* source with *every* target in the group, and the converter keeps that. Decide what the game does when:
- a target has **several sources**, e.g. two solar panels on one door: any one powers it, or all must?
- a teleporter has **several targets**: first, random, or cycle?

Write the answer down. The link list itself doesn't encode it, though a link's `props` can if you need per-link behaviour later.

### 2.4 Test fixture

Hand-write one tiny map, for example 5×3 with one solar panel linked to one door, and use it as a unit test for the loader before converting real maps.

## 3. Set up the editor palette (once)

In the Draw app:

1. Open the palettes button (the top of the colour bar), tap **new**, and name the palette `Game tiles`.
2. Add a swatch for every row of the table in section 1, with the exact colour. For each one, open its colour picker and set the **tile type** (the "Type id" column) and **role** (`source` / `target` / no links).
3. Check: on a map that only uses these colours, the status bar at the top shows no "unknown" count.

Duplicate this palette or export a map from it to share the setup; every exported `.map.json` includes the palette.

## 4. Convert each existing map

For each old PNG map:

1. **Clear the canvas.** Select everything with the Select tool and delete it.
2. **Paste or drop the old PNG** onto the canvas. If legacy colours are detected, a **Convert links** prompt appears in the status bar. The converter places the pasted image for you.
3. **Open the converter.** Use **Convert links** or Settings › Map › *convert legacy links…*, and replace the config with:

   ```json
   {
     "rules": [
       { "hue": 299, "type": "teleporter" },
       { "hue": 290, "type": "teleporter_target" },
       { "hue": 312, "type": "knob" },
       { "hue": 158, "type": "mirror" },
       { "hue": 264, "type": "solar_panel" },
       { "hue": 114, "type": "door" },
       { "hue": 0,   "type": "laser" },
       { "hue": 20,  "type": "laser_aim" },
       { "hue": 118, "type": "rope_pivot" },
       { "hue": 120, "type": "rope_grab" }
     ],
     "hueTolerance": 1,
     "saturationTolerance": 1,
     "minSaturation": 10,
     "minBrightness": 10
   }
   ```

   - **`hueTolerance` must stay at 1.** Door (114), rope pivot (118) and rope grab (120) are only 2–4° apart, and a larger tolerance would mix them up.
   - **Rope swing rules:** if rope swings aren't paired (see the open question), remove those two rules. Instead, recolour the old pivot and grab pixels to their exact colours by hand, or with the eyedropper and brush.
   - **The fixed-colour tiles** (spawn, wall, ladder, jump-through, spikes) already use their exact colours and need no rule. Their hues don't collide with the rules: ladder is about 29° and spikes about 222°, and white and black have 0% saturation, so `minSaturation` skips them.
4. **Read the summary before applying.** It shows the number of groups, how many of each type, the number of links, and warnings for groups with sources but no targets (or the reverse). Compare it with what you know about the level. A warning usually means a pair was drawn with a slightly different saturation in the old map. Raise `saturationTolerance` to 2 if two halves of a pair were drawn 2% apart, but check that it doesn't merge two separate groups.
5. **Apply.** This is a single undo step. Then check:
   - the status bar shows **0 unknown** and **0 invalid links**
   - in the Link tool (`K`), tapping each button, panel, knob, laser or teleporter shows the expected targets
6. **Export.** Use **Download map** (or **Copy map**) to save it as `<level>.map.json` next to the old PNG.
7. **Test the level in the game** using the new loader.

## 5. Clean up

Once every map is converted and plays correctly:

1. Delete the old PNG loader and all hue/saturation code from the game.
2. Delete or archive the old PNGs. The `.map.json` files are now the source of truth.
3. From now on, edit maps in Draw and re-export them. Changing a pairing means editing a link, not recolouring a tile.

## Checklist

- [ ] The rope swing pairing question is decided.
- [ ] Multi-source and multi-target behaviour is decided (2.3).
- [ ] The game loads the hand-written test fixture.
- [ ] The `Game tiles` palette is set up in Draw with types and roles.
- [ ] Each level is converted with 0 unknown pixels and 0 invalid links, and the summary matches a hand count.
- [ ] Each converted level is play-tested.
- [ ] The old PNG path and hue/saturation code are removed.
