# Quota iOS design notes

The iOS surfaces follow the macOS design system in `quota/DESIGN.md`: same level colors, glyphs and copy. These notes cover what is specific to iOS.

## Principles

- **The widget is the product.** Most of the time the numbers are read from the Home Screen or the Lock Screen; the app is for pairing and details.
- **Color means state.** Green when more than 20% is left, orange from 6% to 20%, red at 5% or less (`UsageLevel.color`). Brand color only on the Claude glyph.
- **System first.** Inset grouped lists, SF Pro, semantic colors and `containerBackground(.fill.tertiary, for: .widget)` so light, dark and tinted Home Screens work.

## App

- One section per account: header with glyph (15 pt), provider name (`.headline`, label color) and plan badge (`.caption` medium on a 8% primary capsule); rows with window label, value (`.body` semibold, monospaced digits) + `left`/`used` suffix, a 6 pt usage bar and the reset countdown (`.footnote`, secondary); the account email in the section footer.
- Issues appear as a footnote label with an orange symbol; the "Updated …" time is the list footer.
- Pairing is a form: explanation, server address, 8-digit code (number pad, capped at 8 digits), Pair button with progress and the error in the footer.

## Widgets

- **Small**: up to four rows: glyph (11 pt), short provider name (`.caption2` semibold), value (`.caption` bold), 4 pt bar; "Updated …" in 9 pt at the bottom, orange when older than 30 minutes.
- **Medium**: 2 × 2 grid of the same tiles with the reset countdown (or the window label) under the bar.
- **Lock Screen**: circular gauge of the account closest to its limit (glyph + value); rectangular 2 × 2 of glyph + value; inline "Claude 72% · Codex 63% · …".
- Each row shows the account-wide window closest to its limit (`ProviderSnapshot.tightestWindow`); `Provider.shortName` keeps names short ("Ollama").
- States: not paired ("Open Quota to pair"), unreachable with no cache ("Can't reach the Quota server.").
