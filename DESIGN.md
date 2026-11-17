# Design

Hoop Archive reads like a box score after dark. Each screen answers its question with one big number, and the detail sits quietly around it.

**Reference rule:** the palette (near-black panels, hairlines, one acid-lime accent) came from a user-supplied reference image. Its layouts and components did not. Nothing here should read as a copy of it: no line chart with a lime vertical marker, no lime-outlined alert cards, no number with a lime caps label stacked under it.

Source of truth in code: `mobile/lib/core/theme.dart` (tokens, type, theme) and `mobile/lib/core/widgets/ui.dart` (components).

## Color

Dark only, by design. There is no light theme.

| Token | Hex | Use |
|---|---|---|
| `Hue.ground` | `#0A0A0A` | Screen background, nav bars, tab bar |
| `Hue.panel` | `#131313` | Raised panels, sheets |
| `Hue.raised` | `#1B1B1B` | Avatar discs, pressed fills |
| `Hue.hairline` | `#262626` | Panel borders, dividers |
| `Hue.hairlineStrong` | `#333333` | Pills, rings, dashed chart guides |
| `Hue.track` | `#2A2A2A` | Empty meter and bar tracks |
| `Hue.line` | `#6E6E6A` | Chart lines, non-leading bars |
| `Hue.textHi` | `#F2F2F0` | Primary text, numerals |
| `Hue.textMid` | `#A3A39F` | Secondary text, labels |
| `Hue.textLo` | `#85857F` | Tertiary text, axis labels |
| `Hue.volt` | `#D8F03F` | The one accent |

**Volt has three jobs only:** the active selection (tab, metric, selected season column, selected row), the leader in a comparison, and the head-to-head verdict block, which is the one place volt fills a surface. It is never decoration. Text on volt is `#0A0A0A`.

No gradients, glows, shadows, or blur anywhere. Depth comes from the panel fill plus a 1px hairline.

## Type

SF Pro (the system face) throughout. Numerals are heavy and use tabular figures, so values don't jitter while scrubbing.

| Style | Size / weight | Tracking | Use |
|---|---|---|---|
| `Txt.numeralXL` | 84 / 800 | -3.2 | The hero number on a screen |
| `Txt.numeralL` | 56 / 800 | -2.0 | Head-to-head score |
| `Txt.numeralM` | 28 / 700 | -0.8 | Supporting figures |
| `Txt.numeralS` | 17 / 600 | -0.2 | Table values |
| `Txt.largeTitle` | 34 / 800 | -1.0 | iOS large titles |
| `Txt.title` | 26 / 800 | -0.8 | Player name, sheet titles |
| `Txt.headline` | 17 / 600 | -0.3 | Row titles, section heads |
| `Txt.body` | 15 / 400 | -0.1 | Body |
| `Txt.caption` | 13 / 400 | 0 | Meta lines, notes |
| `Txt.label` | 11 / 600, caps | +1.5 | Labels that name a figure |

Tracked caps sit **under or beside** a number to name it. They are never used as an eyebrow above a heading.

## Components

- **Panel**: `#131313` fill, 1px hairline, 22pt radius. Panels are never nested.
- **Figure**: a number with its label beneath. Labels are tracked caps for stat abbreviations (GP, FG%) and sentence case for words ("stat lines"). It scales down rather than clipping.
- **Hero number**: the number with its meaning set *beside* it ("30.1 | points per game / 2015-16 · GSW / 79 games"). On Archive it reads as a phrase, "3,275 players".
- **StatusPill**: a hairline capsule for compact status, filters, and the season chosen on each Compare slot. It has a volt outline when active.
- **SplitControl**: the platform sliding segmented control (Regular season / Playoffs).
- **CareerChart (season columns)**: one graphite (`#3A3A37`) column per season. The selected season is volt with its value above it, and the career high is labeled "high". Tap or drag to move through seasons, with a selection haptic per season. Switching metric grows the bars to their new heights (420ms ease-out). A missing season is a dash on the baseline, never a zero bar.
- **Career high line**: a quiet row under the chart; tapping it jumps to that season.
- **Shot gauge**: the rate as a figure over a 10-cell segmented gauge (each cell is 10%). It is volt when it is the active metric, grey otherwise, and every cell is empty when the rate is missing.
- **Season table**: rows with a hairline between seasons. The selected row is lifted (`#1B1B1B`) with its season in volt; tapping a row expands the full stat line.
- **Metric duel**: mirrored bars from a center line. The leader's side is volt and its value bold, so the result reads without color.
- **Verdict block**: a solid volt panel with black type, read like a scoreboard: the tally (`7–4`), who leads, and the lines compared.

## Platform (iOS-first)

- A tab bar for Archive, Players, and Compare. Each tab keeps its own navigation stack.
- Large titles on top-level screens and an inline nav bar on profiles. Edge-swipe back is preserved.
- Sheets open on the root navigator so they cover the tab bar.
- SF Symbols (Cupertino icons) only, with 44pt minimum touch targets.
- Motion: season columns grow to new heights when the metric changes, and row expansion eases out over 260ms. Selection tracks your finger directly. All of it is disabled under Reduce Motion.

## Data honesty in the UI

- A missing stat renders as "—" in `textLo`, never as 0.
- Charts show a dash for a missing season, and gauges show empty cells.
- Regular season and playoffs are separate views, never blended.
- A comparison leaves out a metric missing for either player and names it in a note.
