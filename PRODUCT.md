# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Two audiences, weighted equally:

- **Basketball fans** looking up players, reading career arcs season by season, and settling "who was better" debates by comparing two players.
- **Portfolio reviewers** (recruiters, engineers) skimming the app as a showcase. The first impression has to land in seconds, and the app has to hold up as a real stats tool when they dig in.

## Product Purpose

Hoop Archive is a mobile NBA player analytics app built on historical data (1979–2020, about 3,275 players and 17,682 season stat lines), with an optional current-season sync from Sportradar. It lets people browse and search players, open a profile with season-by-season stats and performance trends, and compare two players' career lines metric by metric. Success means finding a player and understanding their career fast, and getting an honest comparison.

## Positioning

An honest stats archive: it never fabricates missing numbers, never treats a missing stat as zero, keeps regular season and playoffs strictly separate, and works offline with clearly labeled saved copies.

## Operating Context

Used on a phone, often in short sessions (checking a player mid-conversation or mid-game). Can be offline; previously loaded data is served from a local cache with a "saved copy · updated …" label and an offline banner.

## Capabilities and Constraints

- Screens: Home (dataset overview + entry points), Players (search, team/position filters, paginated list), Player profile (header, regular/playoff toggle, trend charts, season table), Compare (pick two players, regular/playoff, metric-by-metric leader), Not-found.
- Data rules: missing statistics render as "—", never 0. Unavailable metrics are never compared as zero. Regular season and playoffs are never mixed. Player identity uses ids, not names.
- The Sportradar API key lives only on the backend; the app never sees it. Live data shows as "not configured" until the backend has a key.
- Stack: Flutter (Riverpod, GoRouter, Dio, fl_chart, shared_preferences, connectivity_plus).
- Restructuring the navigation and layouts is allowed; every feature and data rule above must survive.

## Evidence on Hand

- Real historical dataset (Kaggle CSV, license unverified; not redistributed, not committed).
- Player headshots via NBA registry ids where available, with initials as the fallback.
- No testimonials, user counts, or press. Do not invent any.

## Product Principles

1. Truth over polish: a gap in the data is shown as a gap.
2. A number should be readable at a glance; detail is one tap away.
3. Regular season and playoffs are two separate stories.
4. Offline is a normal state, not an error.

## Accessibility & Inclusion

Respect iOS Dynamic Type where practical, maintain WCAG AA contrast for text, and never encode meaning in color alone (leaders and alerts also carry text or shape).
