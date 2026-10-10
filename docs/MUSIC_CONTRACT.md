# Phase 2 music — shared contract

The three Phase 2 tracks (A engine, B Music page, C MOD export/import) work in
parallel. Each one owns its part and relies on the others ONLY through the
interfaces below. Changing anything here needs all three tracks updated.

## 1. Project data (`proj`, owned by Track B, read by Track C)

```
proj.songs = [ song, ... ]            // 0..4 songs, [] in new projects
proj.level_song = array of 10         // per level: song index, -1 = none
                                      // (index 0 is also the single-screen song)

song = {
    name: "Song 1",
    kind: 0,                          // 0 = arranged on the Music page, 1 = imported .mod
    bpm: 125, speed: 6,               // ProTracker tempo / ticks per row
    swing: 0,                         // 0..50 (%), applied when rendering rows
    loop_bar: 0,                      // bar the song restarts at
    arr: { ... },                     // kind 0: Track B's arrangement (lanes, loops,
                                      //   patterns, instruments) - B defines the inside
    mod: undefined or modsong         // kind 1: imported data, see 2.
}
```

In memory everything is plain arrays/structs. Large arrays (sample data)
are packed on save with Track C (Phase 1) helpers `pack_u8` / `unpack_u8`
in `scr_project` — use them, keyed `*_z`, and keep loading unpacked data.

## 2. `modsong` — the neutral song form (owned by Track C)

Both directions go through this one struct:

```
modsong = {
    title: "",                        // max 20 chars
    samples: [ 31 x { name, data /* array of signed 8-bit ints */,
                      volume /*0..64*/, finetune /*-8..7*/,
                      loop_start, loop_len /* in bytes, even; loop_len 0 = no loop */ } ],
    order: [ pattern indices ],       // 1..128 entries
    restart: 0,                       // order position to loop back to
    patterns: [ 64 rows x 4 channels x { note /* 0 = none, 1..36 = C-1..B-3 */,
                                         sample /* 0 = none, 1..31 */,
                                         effect /* 0..15 */, param /* 0..255 */ } ]
}
```

Track C provides (in a new script `scr_mod`):

- `mod_write(_modsong)` -> buffer (u8) holding a standard 4-channel "M.K." MOD.
- `mod_read(_path)` -> modsong, or undefined with a toast on failure.
- `mod_size(_modsong)` -> bytes (for the Build page chip RAM figure).

Track B provides (in its Music page script):

- `song_to_modsong(_song)` -> modsong  (kind 0: render the arrangement;
  kind 1: return `_song.mod`).
- `music_preview_*` mixing in GML (B owns preview; it may call C's
  functions but must not depend on them for the editor to work).

## 3. Data block (owned by Track A, written by `scr_adf` and `adf_reference.py`)

Header grows from 80 to 84 bytes:

```
H_MUSIC  equ 80     ; offset: music table, 0 = no music
HDR_SIZE equ 84
```

Music table (word-aligned, offsets are from data start like every header long):

```
+0   word   nsongs (0..4)
+2   word   0 (reserved)
+4   10 bytes  level song: song index per level (0..nsongs-1), $FF = none.
               Single-screen games use entry 0.
+14  word   0 (pad)
+16  nsongs x { long offset to MOD bytes, long length }
```

The MOD bytes are exactly what `mod_write` returns (standard M.K. layout,
samples in the same block, all in chip RAM). Bump the header `version` word.

New DO actions (rule record unchanged, param = song index for 18):

- `18` play music (param: song index; restarts from the top)
- `19` stop music

The engine starts the level's song (if any) at "level starts", stops it at
game over / win screens, and plays sound effects through ptplayer's
`_mt_playfx` so music and effects share the 4 Paula channels.
