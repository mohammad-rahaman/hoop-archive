---
version: 1
slug: "mobile-lib"
primary_target: "mobile/lib"
related_targets: []
---

# Surface: Hoop Archive app (all screens)

Mode: Operate. Fans and portfolio reviewers look up a player, read a career, and compare two players on an iPhone, often in short sessions and sometimes offline.

Scope: Archive (home), Players, Player profile, Compare, picker sheet, not-found. Restructure allowed; every feature and data-honesty rule in PRODUCT.md survives.

Pinned by the user: their reference image (dark instrument panels, one acid-lime accent, huge numerals, small tracked labels, hairline cards, gray line chart with a lime marker). No gradients.

## Direction contract

THESIS: A career read like an instrument panel. One big number answers the question, and everything else is a quiet gauge beneath it. It refuses the default sports-app look (team colors, gradient hero cards, stat-tile grids).

OWN-WORLD: Near-black ground #0A0A0A, raised panels #131313 with 1px #262626 hairlines at 22 radius. One accent, volt #D8F03F, used only for the active selection, the leader, and the live alert. Gray #6E6E6A lines, #2A2A2A tracks. SF Pro with heavy tabular numerals at -0.04em, 11pt tracked caps labels under the numbers. SF Symbols. No glow, no gradient, no shadow.

STORY: Glance at the number, scrub the career, compare two players, and trust every gap ("—" is never 0).

FIRST VIEWPORT: The profile is the signature. Inline nav bar, then avatar, name, and meta. Below that, a hero panel with an 88pt numeral for the selected season and metric, a volt label under it, and a 180pt line chart. Dragging across the chart moves a volt marker and the numeral with a selection haptic. Metric tabs sit above the numeral.

FORM: Brief-pinned direction (the user's reference image). No roll. seed: none (brief-pinned)

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
