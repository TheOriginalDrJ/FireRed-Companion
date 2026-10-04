# Pokemon Companion — FireRed Recomp v0.1.2

Import `PokemonCompanion-FireRed-v0.1.2.zip` through Recomp's mod manager, enable **Pokemon Companion**, and restart. Replace the previous version rather than enabling two copies. In Options, **POKEMON FOLLOW → ENABLE / DISABLE** controls the companion. Enabled by default. No new save or other mod is required. Uses API 2 and engine-internals permission; targets the locally inspected FireRed Recomp engine with the game3 follower and PMD modules.

Version 0.1.2 lets the first Pokemon continue following at zero HP, including after a map load. Its HP stays unchanged, and its pending gift is preserved.

Version 0.1.1 preserves continuous following across connected route borders. The companion, its active step, animation timing, and queued footsteps are translated into the destination map's coordinates. Failed crossings leave them untouched; the border step contributes exactly one walking step. Native tests cover Pallet Town to Route 1 and isolated offset connections in all four directions. The specific Hoenn Route 124/125 pair has not been playtested with the full Hoenn mod enabled.

The Pokemon in party slot one follows your footsteps, even when fainted. Face it and press **A** to talk. Reordering the party or evolving its leader changes the companion automatically. An egg, empty party, or species absent from Red Rescue Team produces no follower; it does not silently select a different party member.

Every 256 eligible walking steps there is a 25% chance of finding a Potion, Antidote, Poke Ball, or Paralyze Heal. An exclamation bubble remains above the companion while it has a gift. Talk to receive it through the native Bag. A full Bag preserves the gift. One gift can be pending per Pokemon. Walking progress, gifts, and talk counts use the game's `session.modData` save extension and persist when you save normally. Options use the engine's separate Options persistence.

## Extracted assets and data

All artwork comes from the supplied 32 MiB Red Rescue Team USA/Australia ROM, verified as MD5 `2100cf6f17e12cd34f1513647dfa506b`. The package contains **423 sprite sets and 93,591 assembled poses**, covering all **386 Gen 1–3 species**, Unown and Deoxys forms, Castform forms, Munchlax, and special actors. No ROM or engine is included.

Each sprite set includes a transparent PNG atlas, Lua animation groups/sequences with original directional frames, offsets and 60 Hz timing, precise opaque top bounds, and its original 72-byte monster record. `assets/catalog.lua` maps National Dex numbers to PMD assets. `assets/monster-data.json` decodes palette/body/movement information, types, abilities, base stats, evolution fields, recruit rates and portrait availability flags. These are PMD-native values and do not replace FireRed battle data. `extraction.json` records source provenance; `sha256.json` records PNG hashes.

Extraction uses the local engine's `src/import/pmd` decoder. Monster fields follow [pret's MonsterDataEntry definition](https://github.com/pret/pmd-red/blob/master/include/structs/str_pokemon.h). No guessed sprite substitutions are used.

## Current boundaries

- Walking companions temporarily withdraw during cycling, Surf, Fly, and hidden-player sequences, then regroup. Warps and teleports reset their trail; ledges regroup on a visited tile.
- FireRed internal species numbers are converted through the native National Dex mapping. Unown uses personality-selected forms; Deoxys uses FireRed's Attack form. Castform uses its normal overworld form. Original PMD palettes are used, including for shiny party members.
- All extracted poses are retained for future features; the current companion uses directional walk/standing frames. Dialogue is newly authored and responds to low HP. It does not use Mystery Dungeon story dialogue, portraits, voices, hunger, IQ, or dungeon AI. Portraits, learnsets, growth tables, maps and the rest of the game are not extracted by this companion importer.
- The companion is passable and uses the engine's actor draw ordering. This mod owns the game3 follower slot; another follower mod using that same slot is incompatible. Extensive gameplay across every map and third-party rendering pipelines is not verified.

## Rebuild and verification

From this workspace, with Python and Pillow installed:

```
python tools/companion/run_lua.py tools/companion/extract.lua --rom "path/to/Red Rescue Team.gba"
python tools/companion/prepare_assets.py
python tools/companion/decode_records.py
python tools/companion/run_lua.py tests/companion/native.lua
python tools/companion/package.py
```

The harness uses the local `HoennJourney/inspection`, `HoennJourney/tests/love-runtime`, and read-only extracted FireRed cache. It creates a hidden native rendering window and isolated output files. It does not load or write player saves.

Checks cover the real mod sandbox, Options navigation/persistence, player collision and following around a corner, A-button dialogue, deterministic pickup and Bag handoff, full-Bag retention, save roundtrip, party/egg/faint/vehicle/teleport behavior, every atlas and animation sequence, all 386 species mappings, 28 Unown forms and duplicate initialization. Screenshots and a sprite preview are in `outputs/companion-*.png`.
