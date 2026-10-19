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
- [x] The Android system splash shows F1 (the rectangular mark, "Libri" near the bottom) on the app's light or dark background instead of the launcher icon in the phone's icon shape; the wordmark is the font's outlines, traced once (owner's request, 2026-10-18)
- [x] D19 The Deezer lockup shrunk to 22 dp: Deezer's own file makes the heart much taller than the wordmark, so the whole logo is kept small (owner's request, 2026-10-18)
- [x] Actors tag category (canvas revision of 2026-10-18): between Directors and Studios everywhere categories are listed (D10, A2, D14, S9, S10); in D14 only for movies and shows unless searched; A8 suggests the top three billed cast from TMDB as new actor tags
- [x] D14 every group starts folded except the groups holding a tag on this entry and "New on this entry"; folded rows show "n selected"; a search shows matches from every group (canvas revision of 2026-10-18)
- [x] Typography: Bricolage Grotesque dropped; headings are Figtree ExtraBold with -0.03em letter spacing at the same sizes; the font asset removed, the splash wordmark re-traced (canvas revision of 2026-10-18)
- [x] D20 Token expiry warning (canvas revision of 2026-10-18): the `GitHub-Authentication-Token-Expiration` header of every successful sync answer is kept in `connection.json` for the token in use (a date not ahead is ignored, as GitHub sent the current time by mistake in September 2025); from seven days before, D20 once a day on the first app open that day, with Replace token (the token step, repo kept), Open GitHub (the tokens page in the browser) and Later; after the expiry a 401 reads "Token expired" with Replace token on the A12 banner and the D6 card; captures in dark, light and at 1.3; D20 and the expired banner in the accessibility audit; `TOKEN_EXPIRES_IN=6` and `SYNC_BANNER=expired` dev switches
- [x] Seasons for shows (canvas revision of 2026-10-18, A29 to A33): `seasons` on show entries with a status each and a `"new"` mark, the `SetSeasonStatus`, `MarkSeasonsDone` and `AddSeasons` operations; TMDB's seasons when a show is added (out, or at most two weeks away); the daily check for new seasons of shows In progress or Done; rows with the years and the season count and a "New season" badge (A1), the header's years and badge (A30); the Seasons section in details (A29, A31), all seasons (A32), the status sheet with catch-up (A33); seasons added, removed and dated in A8; captures at 360 and 1.3, A31 to A33 in the accessibility audit
- [x] A2, D14, S9: a tag group's header and a long group's row show no press highlight; the group opening, or the full list (A28), is the feedback. Sheets scroll at their full width with the margin inside, so nothing in them is clipped at the margin; the decade row runs to both sheet edges; S7's plan note row is 48 dp tall (owner's report, 2026-10-18)
- [x] A2, D14, S9: a tag group opened low in the sheet scrolls the sheet just enough to show its tags, never so far that its header leaves the top; a group the sheet opens by itself (the first group after the types change) leaves the sheet where it is (owner's report, 2026-10-18)
- [x] Seasons, second round (canvas revision of 2026-10-18, A29 to A37): shows lose their own date; a show's status comes from its seasons (one season: that season's) and is written on every change; Want shows are checked daily too; announced seasons are added and shown "Coming 2027", New only once out; the daily check fills shows without seasons once, keeps announced dates current, writes drifted statuses and removes or asks about seasons TMDB drops (A36); the move to seasons for saved shows; details with the status row (A29) and one-season shows (A34, A35); Edit with season statuses (A37); plan ticks go through the seasons; captures at 360 and 1.3; A34 and A37 in the accessibility audit
- [ ] Data repo follow-up for seasons: `scripts/library.py` accepts `seasons` on shows (key order, optional `new` and `manual` only while true, numbers rising, `"released": null` on a show with seasons), and a show's year and "Coming later" state come from Season 1 (`released_of`); the README's format section says so. Edited in the working tree of `ekmanch/library` on 2026-10-18 and checked against a copy of its `library.json` moved by the app; waits for a commit and push. `libri-scratch` needs no edit: the new build moves its two shows with seasons (Carrie, Haunted Hotel) itself on its first sync
- [x] A1: a show row's badge reads "New season" beside the full subtitle ("2022–2026 · 3 seasons") as drawn; when both do not fit, as at 360 dp beside an In progress pill, the badge shortens to "New", and only then does the subtitle give way with an ellipsis (text scale 1.3) (owner's choice, 2026-10-18)
- [x] Every sheet pulls down to close from anywhere on it, not only the grabber: a scrollable body scrolled to the top hands the pull to the sheet (same close rule: a fling down or more than half gone), while a scroller inside it (the A25 wheels, a sideways row) keeps its own drag (owner's request, 2026-10-19)
- [x] Page count for books (canvas revision of 2026-10-19, A38): `pages` on book entries, after `formats`; filled when a book is added or looked up again, from Open Library's `number_of_pages_median`, else Google Books' `pageCount`; "160 pages" under the author in details, left out without a count; a numeric Pages field in A8 for books
- [x] Data repo follow-up for page counts: `scripts/library.py` accepts `pages` on books (`TYPE_KEYS`, after `formats`; a whole number above zero, else "pages must be a whole number above zero") and the README's format section says so (committed and pushed as `86230d8`)
- [x] Data repo follow-up for Actors (committed and pushed as `188a303`): `scripts/library.py` (`CATEGORIES`, Actors after Directors) and the README's tag rules are edited in the working tree of `ekmanch/library` and wait for a commit and push; the Markdown, `tags.md` and the README vocabulary regenerate from the JSON by themselves (pre-commit hook and the Action), and `libri-scratch`'s `library.json` gets its `"Actors"` list the first time the app saves an actor tag
- [x] Tags may hold a dot between two digits (#2.5d); the app cleaned a typed tag only partly, so `2.5d` reached `libri-scratch` while `library.py` rejected it. `normalizeTag` now keeps a tag to the data repo's rule (other punctuation becomes a hyphen, diacritics fold) and the similar check ignores dots like hyphens (owner's report, 2026-10-19)
- [x] Episodes for shows (canvas revision of 2026-10-19, A39, A40): season rows in details and in all seasons end with a chevron and open the season, all but the status pill; the header with the show, the season, its date and episode count ("4 of 6 episodes out" while airing) and the season's status pill (A33); the episode list with number, title, air date and runtime, the date in the header only when all came out on one day, episodes not out dimmed with "Airs Oct 22" and "Title TBA"; fetched from TMDB on open and kept on the phone (`<cache>/libri/episodes/`), fetched again only while airing, pruned with the show; never in `library.json` or the daily check; captures at 360 and 1.3; A39 in the accessibility audit
- [x] One-season shows like the others (canvas revision of 2026-10-19, A34, A35, A37, A41): details always list a show's seasons; with one season, Season 1's row has no pill and opens its season (A41), and the Status row holds its pill, the sheet titled with the show; a second season turns the row read-only and gives every season its pill; in Edit a one-season show keeps the Status control and Season 1 has no pill; captures of A34 with its sheet and A41 at 360 and 1.3
- [ ] Data repo follow-up for the dot in tags: `scripts/library.py` (`TAG` allows a dot between two digits) and the README's tag rules are edited in the working tree of `ekmanch/library` and wait for a commit and push
- [ ] `test/data/repository/github_library_repository_test.dart` "watching alone loads the queue and checks, like the UI" fails now and then under the full suite (one request seen, two expected: the check has not finished after `pumpEventQueue`); it passes alone. Seen 2026-10-18
- [ ] The accessibility audit's "filter" step fails in dark and light ("Bad state: No element" tapping the `#horror` chip in the filter sheet, `test/accessibility/a11y_audit_test.dart` line 180), so A2 and L5 are not audited; seen on 2026-10-18, present before the branch step too
- [ ] The accessibility audit's text scale 1.3 walk stops at its "details" step ("Bad state: No element", `test/accessibility/a11y_audit_test.dart`) and skips the five steps after it; it did so before phase 6 too. Make the walk reach every screen at 1.3 again.

## Later

- [ ] Revisit whether entry details show the cover whenever a title is opened, not only in a photo view (decision 19 of the 1g audit: keep the current behavior for now)

- [ ] Linux desktop layout
- [ ] Split `library.json` per type if it grows too large
- [ ] General "Show cover images" data-saving option
- [ ] Store the album's lookup id on song entries so D12 (saving an album when its songs exist) can match by id, as D13 does
- [ ] Move lookup API keys off the device: research a small proxy (Cloudflare Workers free tier as first candidate) that holds the TMDB/IGDB/Google Books keys as server secrets and forwards lookup requests, so no key is compiled into the APK. Consider Play Integrity to limit who can call it. Only needed if the app is ever distributed beyond my own phone.
