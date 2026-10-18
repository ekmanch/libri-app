# TODO

Build order for Libri. Screen IDs (A1, S5, D12 …) refer to artboards in `design/canvas.html`; decisions are in `docs/DESIGN.md`.

Phase 1 builds the whole UI on fixture data, with nothing saved and no network. Functionality is wired up from phase 2.

## Phase 0: Project setup

- [x] Create the Flutter project (Android first; Linux desktop as a dev and test target only)
- [x] Add `lib/theme/app_theme.dart`, the fonts (Bricolage Grotesque, Figtree) and check that it compiles
- [x] Add Riverpod
- [x] Define the models from DESIGN.md section 8 (Entry, Track, Plan, PlanItem, tag categories) with freezed, plus the canonical JSON codec
- [x] Define the `LibraryRepository` interface and the starter set of operations
- [x] Create `assets/fixtures/library.json` in the v2 format with realistic data for all six types, a Halloween and a Christmas plan, and music with albums, songs and rated tracks
- [x] `FixtureLibraryRepository`: loads the fixture, keeps changes in memory only
- [x] Set up `integration_test` with a smoke test and run it on Linux

## Phase 1: UI on fixture data

### 1a. Shell and shared pieces
- [x] App shell: floating pill navigation (Library, Plans) and round "+" button
- [x] Shared widgets: entry row (title, italic subtitle, status mark), section heading in type color, status segmented control, tag chip, bottom sheet frame, dialog frame, buttons (primary, outline, neutral, destructive = neutral fill with red text)
- [x] Theme switching (dark, light) and accent switching, live (state only; the Settings UI is 1f)

### 1b. Library
- [x] A1 Library home: type chips, active plan card, two entries per type under headings with counts
- [x] A1 Library in the pill returns to the home from any type view: All (chip row slid back into view), status reset, filter cleared, scrolled to the top (like Plans returns to S5)
- [x] A4 Type picked: the home becomes the type's list in place, with status segments, count, sort, view button
- [x] D1 Sort menu
- [x] A20, A21 List with covers and grid with covers (placeholder images)
- [x] View menu (as A16) and remembering the view per type
- [x] A2 Filter sheet: type, status, released, tags in collapsible groups, "Include seasonal-only" switch
- [x] L5, L6 Filtered results with removable chips
- [x] A5 Search
- [x] A10 Empty states
- [x] L1, L2, L3 Long lists: section headers (decade, month added, letter) with a jump rail on the right in the text and list views, shown when the list is three screens tall or more and has two sections or more
- [x] L4 Long grid: draggable thumb with a label bubble instead of headers, same rule
- [x] L5, L6 Long filtered results: sections by sort for one type, by type with a dot rail for several

### 1c. Entry details and editing
- [x] A6 Entry details sheet: cover spot, status, rating row, note, about, tags, plans, edit, delete
- [x] D11 Rating picker
- [x] A13 New entry: pick a match (static fixture results)
- [x] A8 Add / edit entry form, including the tag picker
- [x] D9 Similar tag warning and D10 New tag: confirm and pick a category
- [x] A7 Add to plan
- [x] A9 Delete confirmation

### 1d. Music
- [x] A14 Artists list: Artists / Albums / Songs toggle, letter headers, alphabet rail, "Various Artists" pinned last, leading "The" ignored when sorting
- [x] A14 Music replaces the status segments and the sort link with the tab toggle and one count line ("17 artists, 13 albums, 5 songs"); the view choice is remembered per tab (added after the canvas revision)
- [x] A16 View menu (shared since 1b), A17 list with photos, A18 grid
- [x] A15 and A19 One artist: Albums and Songs sections, text and photo versions
- [x] Albums tab and Songs tab (flat lists); the Songs tab lists song entries and rated tracks together
- [x] A22 Album details with track ratings (static track lists for two fixture albums stand in for the lookup; other albums show only their rated tracks)
- [x] Album / Song switch in the entry form, with the optional album field for songs
- [x] D12 and D13 Replace dialogs

### 1e. Plans
- [x] S5 Plans overview
- [x] S1 Plan checklist, grouped by type
- [x] S2 Timeline view (left rail, fills to today)
- [x] S4 All entries for a plan's tags: add, edit, remove
- [x] S7 and S8 Entry details inside a plan (with and without "When")
- [x] D2 When picker: a day or a period
- [x] D3 Plan menu, S9 Edit plan, S10 New plan (including copy to a new year); then the "New plan" link at the end of A7
- [x] D4 Remove from plan or delete everywhere, D5 Delete plan
- [x] S11 and S12 Seasonal themes (Halloween, Christmas): strip, title icon, progress marker, seasonal accent
- [x] Year chip on the plan header: switch between plans with the same name, "New year…" copies the plan (added after the canvas revision)
- [x] "This plan / All #tag" tabs on the plan screen; S4 rows get Add / In year, and Edit entry, Remove #tag, Delete behind "⋮"; the "+" button changes with the tab (added after the canvas revision)
- [x] S10 "Start with: Empty / Copy a plan", S5 "Next up" on the active card, a plan note editor from S7 and S8 (added after the canvas revision)
- [x] Capture every screen, sheet and dialog built so far, also at the S25's 360 dp and at text scale 1.3; one shared search field for every search box

### 1f. Settings and states
- [x] S6 Settings: theme, accent color (Vivid and Pastel groups), timeline default, seasonal theme default, About row (name and version); also the default game platform from the canvas, used by A8
- [x] D6 Library connection (UI only)
- [x] F1 to F7 First run (UI only): splash, welcome, connect GitHub, new or existing library file, create, pick, all set (replaces the old first-time setup artboard; F4 to F7 became F5 to F8 when the branch step was added in phase 6)
- [x] A12 Sync and error banners, D7 First load (driven by fake states)
- [x] D8 Light theme pass over every screen (every screen is captured in light by `screenshots_test.dart`; a reviewer compared them and the banners, the inset status segments and the type-chip dots were fixed)

### 1g. Phase 1 wrap-up
- [x] Screen sizes pass: every screen at 360 (Galaxy S25), 402 (iPhone 17), 412 (Galaxy Ultra and Plus) and 440 dp (iPhone 17 Pro Max), each at text scale 1.0 and 1.3; fixed widths that break become flowing layouts
- [x] Walk through every artboard next to the app and list the differences (three independent reviews; the differences and the owner's decisions are fixed and recorded in DESIGN.md)
- [x] The tag search boxes in the filter sheet (A2), the tag picker (D14) and Edit plan (S9) are the shared `SearchField` with the magnifying glass
- [x] D6: both outline buttons use the artboard's button outline; "Check for changes" is a two-line row
- [x] Reconsider the "See all" link: it jumps to a different screen (A4) and that was not intuitive. A clearer label or a different affordance. (Resolved by the canvas revision of 2026-10-10: the type view is the home with a chip picked.)
- [x] Accessibility pass: contrast, touch targets, screen reader labels, large font scale (`test/accessibility/a11y_audit_test.dart` walks every screen in dark, light and at 1.3; 48 dp targets, AA inks and type colors except Movies by decision)
- [x] Widget tests for filtering, sorting, the similar-tag check and the replace dialogs
- [x] The filter sheet and the home stay in sync: the sheet opens with the picked type and status segment, and one type plus at most one status shows as the type view (A2)
- [x] Movies and music have no In progress status; the filter sheet's status chips follow the chosen types
- [x] Kind filter (Albums, Songs) for music in the filter sheet; Music + one kind is that Music tab (A23, A24), and the sheet opens with the picked tab's kind (A3)
- [x] Tag categories split: Genres, Game genres, Music genres, Mood; the filter sheet shows only the groups the chosen types use, and the tag picker hides other types' genres (A2, D10, D14)

## Phase 2: Local data

- [x] Persist the library to a local file through a `LocalLibraryRepository`, so changes survive a restart (`library.json` in the app documents directory, seeded from the fixture on a new install; `LONG_LISTS` stays in memory)
- [x] Operations layer: every change is a small named operation with a human-readable summary (`LibraryOperation.summary`, e.g. "Mark The Mummy as done")
- [x] Store display preferences on the device (`preferences.json` behind `PreferencesStore`, never synced)
- [x] Rewatch detection: adding a Done entry to a plan marks the plan item as a repeat (done in A7, phase 1c)

### 2a. Differences found by the phase 2 capture review

Phase 2 changed no UI; a reviewer compared every capture with its artboard and found these older differences. Some may already be settled by the phase 1g walkthrough; check before fixing.

- [ ] D6 and S6: the values in the setting rows (Repository, Data file, Access token, Library source, Version) sit mid-row; the artboards put them flush right
- [ ] S2: the timeline card's type label sits above the title even at text scale 1.0 on a 360 dp phone (the narrow threshold in `plan_screen.dart` is always hit); DESIGN.md 10a allows this only at a large text size
- [ ] A22, S7, S8: the album details and the plan entry sheets have no cover spot, unlike the artboards and A6; A6 at text scale 1.3 hides it too
- [ ] F3: "How do I create a token?" looks disabled (dim grey); the artboard draws it in the normal foreground
- [ ] Minor: the A1 card's "X of Y done" sits on the title row, not the ACTIVE PLAN row; the A13 match subtitles and A18 artist names cut to one line instead of two; the A21 Done badge colors are inverted and a one-line title leaves a gap above the year; A19 count and sort are on two rows; the A10 icon is the filter sliders, not the magnifier; the A8 creator field cuts its text with no ellipsis; the L5 "Clear all" wraps; the S4 action row wraps; the S5 Not started row says "Linked to #christmas" instead of "4 entries · starts Dec 1"; the L3 letter rail is packed into the middle

## Phase 3: Migrating the data repo

Done in `ekmanch/library` on the branch `feature/app-preparation` (2026-10-13), plus the id scheme change here. Each step needs my go-ahead.

- [x] On a feature branch in `ekmanch/library`, reverse the pre-commit hook so JSON is the source and Markdown is generated from it
- [x] Script that converts today's `library.json` (v1) to v2: flat entries, `dropped` becomes `dnf`, `year` becomes `released`, "Compilations" becomes "Various Artists", plan rows become `want` entries tagged with their season, seasonal favorites merge into entries, in-progress movies and albums become `want`
- [x] The migration script writes the file in the app's canonical encoding (see DESIGN.md section 8), so the app's first save is not a full rewrite
- [x] Check the id scheme for books, games, shows and anime against today's ids before migrating (one scheme everywhere: apostrophes dropped, books use title + year; `slugify` changed, `tool/assign_ids.dart` assigned every migrated id with `EntryId.generate`)
- [x] Generate the Markdown files and PDFs from the JSON (GitHub Action), instead of the other way around
- [x] Verify nothing was lost: entry counts per type before and after (670 v1 titles, 679 v2 entries: 605 catalog + 65 seasonal-only + 9 new from plan rows; no title missing, lists regenerated and diffed)

## Phase 4: GitHub sync

Built on 2026-10-13; the decisions are in DESIGN.md section 10b.

- [x] F3 to F6 First run for real: token and repo, stored in secure storage (the token in `flutter_secure_storage`, the connection in `connection.json`; F3 validates the token and keeps the default branch, F5 commits the empty library, F6 lists the repo's JSON files)
- [x] `GitHubLibraryRepository`: read with a conditional request, always in raw format
- [x] Show cached data first, then refresh on open, on resume, on pull-to-refresh, and on tab switch after 5 minutes (plus every 5 minutes in the foreground, as D6 promises)
- [x] Save: bundle edits for 2 to 3 seconds into one commit with a readable message ("Mark The Mummy as done")
- [x] Conflicts: refetch and re-apply the pending operations
- [x] Offline queue (`pending.json`, survives a restart; a save whose answer was lost is settled before anything is sent again)
- [x] A12 banners driven by the real sync state; Retry re-sends, "Sync now" in D6 syncs
- [x] F3 "How do I create a token?" opens GitHub's token page (needs url_launcher)
- [x] Confirm before Disconnect in D6, since it clears the token
- [x] Read the version for About from the build (package_info_plus)
- [x] Opt-in live test against `ekmanch/libri-scratch` (create, conditional read, save, stale sha, a file over 1 MB); the device check on the S25 is the owner's
- [x] Lock the app to portrait (manifest and `main()`)
- [x] D1 "Rating, highest first": 10 down to 1, unrated last, ties by title; rail sections are the ratings that exist
- [x] A25, A26 Released as a wheel picker (year, month, day; tap the year to type it) in place of the text field
- [x] D15, D16 Disconnect in two steps: confirm, then keep the library on the phone (local mode, D6 offers "Connect to GitHub") or delete it (first run at F2)
- [x] Sync as a three-way comparison against the base in `sync.json` (blob shas): push, pull, or stop at a conflict; a stale-sha refusal is checked, not retried; the base knows which file it is about, so a kept library reconnected to the same file is compared
- [x] Verified that the data repo's `library.json` and the app's codec produce the same bytes, and that the repo's hook never writes it
- [x] A27, S15, D17 Conflict: the banner with Choose on Library and Plans, Choose in D6, and the dialog (Keep mine / Keep GitHub's / Decide later)
- [x] D18 Reconnecting a kept library to another file asks which library to keep; "Create a new library" (F6) creates it from the phone's library

## Phase 5: Lookups and images

Built on 2026-10-15; the decisions are in DESIGN.md section 10 and 10c.

- [x] A13 Pick a match for real: TMDB (movies, shows), AniList (anime), Open Library with a Google Books fill-in (books), IGDB (games), Deezer (albums, songs); loading, offline, "not set up" and partial-failure states; the full details fetched on the pick
- [x] Fill in released, creator, description, album, platforms and tag suggestions from the match, and the lookup id into `source`
- [x] Covers and artist photos in the photo views, cached on the device; entries without a `source` are matched on the device (`artwork.json`), never written back; pruned once per session
- [x] Track lists for A22 from Deezer, cached on the device; ratings stored under earlier ids still match by title
- [x] API keys kept out of the repo: `secrets.json` (git-ignored) through `--dart-define-from-file`, `secrets.example.json` committed; a missing key means "not set up", never a crash
- [x] "Look up again" from A8: A13 as a picker on the entry's type and title; a pick sets `source`, fills only the empty fields and replaces the device-matched cover
- [x] Opt-in live test against the real providers (`LIBRI_LIVE_LOOKUPS=1`)

## Phase 6: After the first week on the phone

Owner feedback of 2026-10-16 and the canvas revision of the same day (A2, A28, D10, D14).

- [x] A1 The home's header scrolls with the list, like an Android list with a header; the pill and the "+" button stay; a list shorter than the screen does not scroll
- [x] A1 The count row (count, sort, view) pins at the top; the chips, the status segments, the music tabs and a filter's removable chips scroll away (owner's second and third look, 2026-10-17)
- [x] Library in the pill: pop a pushed screen first, then scroll the home to the top, then return to All (DESIGN.md section 3)
- [x] Tag categories: Creators split into Authors, Directors and Studios by main role; the data repo's `library.json` and `scripts/library.py` follow (edited in the working tree, to be committed and pushed before the new build is installed)
- [x] Every tag group listed A to Z by the tag, a leading "the" ignored (A2, D14, S9)
- [x] A2, D14, S9: a group over 24 tags is a row ("Authors · 64 authors · 1 selected ›") that opens A28
- [x] A28 One long tag group, full screen: search, letter headers, the index rail, a check per row, live toggles into the sheet underneath
- [x] A8 The creator field suggests its tag (#stephen-king, #naughty-dog), in its creator group; studios whose name is the brand (Studio Ghibli, Pixar, Disney, DreamWorks) are suggested instead of the director, from the lookup's companies
- [x] `LONG_LISTS` pads the Authors group too, so A28 can be tried on a device; captures of the scrolled home, the long group row and A28 at 360 and at 1.3; A28 in the accessibility audit
- [x] D10 with ten category chips is tall; checked at text scale 1.3: the dialog still fits the 780 dp screen without scrolling, so the chips stay; its "Create tag" button wrapped onto two lines, so button labels now shrink a step instead of wrapping
- [x] `library.json` written by the app had Studios after Other: a new tag category was appended to the map instead of placed in `TagCategory` order, which the data repo's `library.py` rejects. The codec and `AddTag` now keep the categories in declaration order, and a file saved with the old order comes back in order on its next save (owner's report, 2026-10-17)
- [x] F4 Pick a branch between Connect GitHub and the file choice (canvas revision of 2026-10-18; F4 to F7 became F5 to F8): the default branch first with a Default badge and preselected, the rest A to Z, each with when it was updated, a loading line while they load; the branch is saved with the connection and used for the file list, the new file and every read and commit; the step labels read "Step N of 4"; D6 gets a Branch row under Repository
- [x] After the first run, also a reconnect from D6, the app always opens on the library home with All picked (owner's request, 2026-10-18)
- [x] A deleted file, branch or repo (GitHub answers 404) shows "Library not found on GitHub" with what is gone and a Fix button to D6, instead of "Could not save" with a Retry that cannot help; edits stay on the phone and a restored file syncs again (owner's request, 2026-10-18)
- [x] D19 About, opened from the Libri row in Settings (canvas revision of 2026-10-18): the app icon, name, version and build from the build, Open-source licenses (Flutter's license page) and a Data sources list where each row opens the service's website; TMDB with its official logo and required sentence; AniList added and Wikipedia dropped, since the code asks the former and never the latter
- [x] D19 Deezer's developer guidelines require a clearly visible Deezer logo: the Deezer row shows the official logo from Deezer's newsroom, in its light and dark variant; the TMDB logo shrunk from 26 to 13 dp so neither shouts (owner's request, 2026-10-18)
- [x] Android launcher icon from `assets/logos/libri`: adaptive layers (peach and paper background, the mark as foreground, a monochrome layer for themed icons), the squircle and round legacy icons for every density, `roundIcon` in the manifest (owner's request, 2026-10-18)
- [ ] The accessibility audit's "filter" step fails in dark and light ("Bad state: No element" tapping the `#horror` chip in the filter sheet, `test/accessibility/a11y_audit_test.dart` line 180), so A2 and L5 are not audited; seen on 2026-10-18, present before the branch step too
- [ ] The accessibility audit's text scale 1.3 walk stops at its "details" step ("Bad state: No element", `test/accessibility/a11y_audit_test.dart`) and skips the five steps after it; it did so before phase 6 too. Make the walk reach every screen at 1.3 again.

## Later

- [ ] Revisit whether entry details show the cover whenever a title is opened, not only in a photo view (decision 19 of the 1g audit: keep the current behavior for now)

- [ ] Linux desktop layout
- [ ] Split `library.json` per type if it grows too large
- [ ] General "Show cover images" data-saving option
- [ ] Store the album's lookup id on song entries so D12 (saving an album when its songs exist) can match by id, as D13 does
- [ ] Move lookup API keys off the device: research a small proxy (Cloudflare Workers free tier as first candidate) that holds the TMDB/IGDB/Google Books keys as server secrets and forwards lookup requests, so no key is compiled into the APK. Consider Play Integrity to limit who can call it. Only needed if the app is ever distributed beyond my own phone.
