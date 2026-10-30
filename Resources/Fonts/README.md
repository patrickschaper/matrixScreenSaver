# Rezmason Matrix fonts

Original, unmodified TrueType fonts from [Rezmason/matrix](https://github.com/Rezmason/matrix),
pinned to commit `5ba90490453ceceb6812d6b1bc658a99a92411d0`.
Copyright (c) 2018 Rezmason. The upstream MIT license is reproduced verbatim in
`LICENSE.txt`; distribute it with the fonts.

Upstream paths at that commit:

- `assets/Matrix-Code.ttf` → `Matrix-Code.ttf`
- `assets/Matrix-Resurrected.ttf` → `Matrix-Resurrected.ttf`
- `LICENSE` → `LICENSE.txt`

Download base: <https://raw.githubusercontent.com/Rezmason/matrix/5ba90490453ceceb6812d6b1bc658a99a92411d0/>

SHA-256 checksums:

```text
5dff3023c91291d28dffc32fd74f5edbbca1969f25077d0499b1f000cabdec5b  Matrix-Code.ttf
cad5cb197237f3eeed8d5d251df9c058caeb8179dc97494bb19447d2cf3ca4fc  Matrix-Resurrected.ttf
65333257cebb87e8af86201a65f0e550d65b3cf5a468bfee2a69c9d2b5d21123  LICENSE.txt
```

## Verified character mappings

These mappings were inspected directly from the TTF `cmap`, `name`, and `glyf`
tables with FontTools. All Unicode cmap subtables agree. Family, full, and
PostScript names are respectively `Matrix-Code` and `Matrix-Resurrected`;
both use the `Regular` subfamily.

**Classic TTF repertoire:** 57 nonblank mapped glyphs. Their Unicode code points (hexadecimal)
are the following explicit set, not a contiguous range:

```text
0022 002A 002B 0030 0031 0032 0033 0034 0035 0037 0038 0039
003A 003C 003E 007A 007C 00A6 00A9 254C 25AA 30A2 30A6 30A8
30AA 30AB 30AD 30B1 30B3 30B5 30B7 30B9 30BB 30BD 30BF 30C4
30C6 30CA 30CB 30CC 30CD 30CF 30D2 30DB 30DE 30DF 30E0 30E1
30E2 30E4 30E8 30E9 30EA 30EF 30FC A78A E937
```

**Resurrections:** the TTF contains **138**, not 135, nonblank mapped glyphs:
the inclusive private-use range **U+E900–U+E989**. Every character maps to a
different glyph ID with nonzero-width and nonzero-height outline bounds.
Upstream `js/config.js` specifies 135 active slots for its separate MSDF texture.
Direct atlas comparison confirms those slots match **U+E900–U+E986**, in order.
U+E987, U+E988, and U+E989 contain artwork matching inactive atlas slots
153, 154, and 155; exclude them when reproducing the website's active set.
Do not infer the TTF repertoire or atlas ordering from upstream's 57-entry
`glyph order.txt`.

Both fonts additionally map U+0000, U+0001, and U+0020 to separate glyph IDs
with identical degenerate outlines: three points at (0, 0). Those are blank,
despite their nonzero contour count. Exclude the controls; retain U+0020 only
for Classic's intentional blank atlas slot, described below.
Space has advance width 512; the two control characters have zero advance.
There are no shared-glyph-ID aliases in the Unicode cmap and no other exactly
identical coordinate/contour/flag outlines. The Classic font also has unmapped,
empty `.notdef` and `nonmarkingreturn` glyphs; Resurrections has an empty
`.notdef` glyph. Glyph counts therefore differ from drawable character counts.

## Website atlas equivalence

Compared the pinned upstream `assets/matrixcode_msdf.png` (512×512, 8×8 cells)
and `assets/resurrections_msdf.png` (832×768, 13×12 cells) against Pillow/FreeType
renders of every Unicode-mapped character in the corresponding TTF. Atlas
indices below are zero-based, row-major from the top left; each cell is 64×64.
The website uses the first 57 and 135 slots respectively.

Extracted atlas masks with `median(R, G, B) > 127`, cropped each mask to its
ink bounds, resized to fit a 96×96 canvas **preserving aspect ratio**, and
compared intersection-over-union against similarly normalized TTF masks
rendered at 512 pixels. Every nonblank active slot had a unique best match.
Lowest winning IoU: Classic 0.8673, Resurrections 0.8524. Smallest winning
margin over the runner-up: Classic 0.1420, Resurrections 0.0808. Normalizing
width and height independently is unsuitable: it confuses squares with bars.

**Classic website sequence (57 slots):**

```text
30DB 30A2 0033 30A6 blank 30BB 00A6 003A
0022 E937 30DF 30E9 30EA 254C 30C4 30C6
30CB 30CF 30BD 25AA 30FC 003C 003E 0030
007C 002B 002A 30B3 30B7 30DE 30E0 30E1
30E2 30A8 30E4 30AD 30AA 30AB 0037 30B1
30B5 30B9 007A 0031 0035 0032 30E8 30BF
30EF 0034 30CD 30CC 30CA 0039 0038 30D2
0030
```

- Slot 4 is entirely black in the original RGB texture: a genuine blank slot.
  Represent it explicitly as blank (or U+0020 in a fixed-cell renderer).
- Slots 23 and 56 have identical thresholded masks and both match U+0030.
  Preserve both entries to reproduce the website's weighting.
- Thus the 57 slots comprise **55 distinct visible glyphs**, one duplicate
  zero, and one blank. The visible set is the Classic TTF repertoire above
  **minus U+00A9 and U+A78A**. U+A78A matches inactive atlas slot 57;
  U+00A9 is absent from the active atlas set.

**Resurrections website sequence:** exactly **U+E900–U+E986 inclusive**,
135 distinct visible glyphs, with slot `i` matching `U+E900 + i` for all
`0 <= i < 135`. All matches were checked, not inferred from the endpoints.
No active blank slot or repeated character mapping. Slots 135–152 are blank;
slots 153–155 match the three excluded TTF characters U+E987–U+E989.

Atlas SHA-256 checksums (investigation inputs, not bundled assets):

```text
1fd4ed52f8e9cc4af6eaad69d28cd289bf6486f15f00c952548ff0533d6a83ab  matrixcode_msdf.png
f2bfe884b08cacf6c8be09573442d51c5dc5e97bbd8f86bcd86177d4e4b14c79  resurrections_msdf.png
```

Validation: downloaded font/license files were compared byte-for-byte with the pinned raw
upstream files, SHA-256 hashed, and parsed with FontTools checksum checking.
Native CoreText rendering and packaged-bundle loading are separate integration
checks and were not performed as part of this asset import.
