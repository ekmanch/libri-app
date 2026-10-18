# Libri: settled design

Everything here was decided during the design phase. Screen IDs refer to artboards in `design/canvas.html`. Items under "Open" in section 10 are not decided yet.

## 1. What the app is

- A phone-first Flutter app for Android (Samsung Galaxy S25). A Linux desktop build may follow.
- Portrait only: the Android manifest locks the activity and `main()` sets the preferred orientation, so no screen needs a landscape layout.
- Front end for the private repo `ekmanch/library`. `library.json` in that repo is the source of truth.
- The app adds, edits and deletes entries from day one, and writes the changes back to the repo.
- Six types: Movies, Shows, Books, Games, Music, Anime. The word in the UI is "Type".

## 2. Words and rules used everywhere

| Thing | Decision |
|---|---|
| Statuses | Want, In progress, Done, DNF. Movies and music have no In progress: a movie or an album is watched or heard in one sitting, so it goes straight from Want to Done. Music has no DNF either: a song is minutes long, so "did not finish" only makes sense for long-form media. Movies keep DNF. Shows, books, games and anime have all four. |
| Rating | 1 to 10, optional, picked in a sheet (D11), never a slider |
| Favorite | The `#favorite` tag stays, alongside the rating |
| Row content | Title plus an italic subtitle. Subtitle is the year; for books and music it is creator and year; for a song it is album and year. No tags in rows. |
| Not released yet | Subtitle reads "Not released yet" |
| Note vs About | Note is my own text. About is the description fetched from a lookup. |
| Delete | Lives in the details sheet. Every destructive button (Delete, Delete plan, Delete everywhere, Disconnect, Replace…) has no fill, the grey button outline and red text; never a red fill, never next to an accent button. |
| Spelling | American, sentence case |
| Type order | Wherever entries are grouped by type (home, filtered results, plan checklists, the pool), the groups follow the global order: Movies, Shows, Books, Games, Music, Anime. An artboard showing another order is incidental. The timeline groups by time instead and uses this order inside each bucket. |

## 3. Navigation

- Floating pill at the bottom with two destinations: **Library** and **Plans**. A round "+" button sits to its right.
- Settings is reached with a gear icon on top-level screens.
- Inside a plan, "⋮" opens the plan menu (D3).
- No tinted header bars.
- Tapping the current tab's item in the pill returns to that tab's overview one step at a time. A screen above the overview is popped first (Plans to S5, Library to the home). On the Library home the next tap scrolls back to the top, so the title, the search box and the chips are in view again, and the tap after that returns to All: the filter and the type cleared, the status segment reset, the chip row slid back so All is in view (A1). Settled 2026-10-16, after the first week on the phone.
- Each tab keeps its own stack. A shortcut to something another tab owns switches to that tab with that tab's overview underneath, so back lands there: "Active plan" on the home opens the plan on Plans. Shared detail views (entry details, an artist, an album) stay in the tab they were opened from: an entry opened from a plan stays in Plans, one opened from the library stays in Library. Full-screen forms, search and Settings open above both tabs.

## 4. Screens

### Library (A row)

| ID | Screen | Notes |
|---|---|---|
| A1 | Library home | The whole top of the screen is part of the list's scroll. The title, the banner, the search box, the type chips and the status segments (the music tabs, the removable chips of a filter) scroll away with the entries; the count row (count, sort, view) pins at the top as it gets there, so a scrolled list reads "count row, entries" (settled 2026-10-17 after a day with the fully scrolling top and a try with the chips pinned too). The top comes back when the list is scrolled back up or Library is tapped in the pill (section 3). The pill and the "+" button always stay. The jump rail starts under the pinned rows and grows as the rest of the header leaves. A list shorter than the screen does not scroll at all. Type chips; active plan card; two entries per type under a heading that shows the type's count. Rows are ordered In progress, then Want (newest added), then Done, then DNF. Tapping a heading or a chip picks that type, and the home becomes the type's list in place (A4) with no separate screen: status segments, count, sort and view replace the plan card and the headings, and the search hint becomes "Search movies". Picking a type resets the status segment to All. The active plan is the first plan with items that are not all done; finished plans live on S5. Seasonal-only entries are hidden from the home, the type lists and filtered results unless the switch in A2 is on; search still finds them. |
| A2 | Filter sheet | Type, Status, Kind, Released, Tags. Within Type, Status, Kind and Released any choice matches; all selected tags must match. Tags are in collapsible groups by category, only the groups the chosen types use (section 7). Released is a scrolling row built from the library: one chip per decade, labeled with the full decade ("1980s", not "80s"), from the earliest to the latest decade that has an entry, gaps filled in so the row never jumps, plus Older when anything is from before 1960. A new decade appears as soon as an entry from it exists. Has an "Include seasonal-only" switch; when on it counts as one active filter and shows as a removable chip. The Status chips follow the chosen types: In progress only shows when a chosen type can have it (or no type is chosen), and a status the chosen types cannot have is dropped. Kind (Albums, Songs) shows under Status only while Music is chosen, narrows music entries only, and is dropped when Music is unticked. The sheet and the home stay in sync (A3, A11, A23, A24): anything the home's chips can show is not a results screen, anything more opens results (L5, L6). A filter with exactly one type keeps that type picked underneath, so removing the extra filters lands on that type's view; a filter with no type or several types puts the home on All. "Clear all", "Clear filters" and the sheet's Reset clear the type, the status segment and the music tab too. |
| A3 | Filter opened from a type view | The sheet starts with what the home shows: the picked type and its status segment (Movies + Done), or Music and the music tab's kind (Albums or Songs). Music on Artists starts with Music only, since Artists is a way of browsing, not a filter. On All it starts with nothing chosen. |
| A4 | Type picked, text view | The home with a type chip picked: status segments, count, sort link, view button. A status with nothing in it shows one line, "Nothing marked want yet." |
| A5 | Search | |
| A6 | Entry details sheet | Cover spot, status, rating row, Note, About, tags, plans, Edit, Delete |
| A7 | Add to plan | |
| A8 | Add / edit entry | Rating row opens D11. Tag picker is the only place tags are created. Released is a field-shaped button that opens the wheel picker (A25) and shows "2013", "Jun 2013" or "Jun 14, 2013", or "Not set"; it is wide enough for the longest date. |
| A9 | Delete confirmation | |
| A10 | Empty states | |
| A11 | Filter result: one type and one status is the type view | One type with at most one status, and nothing else, shows that type's view with the status segment picked, and the sheet's button reads "Show 5 movies". Music has no status segment, so music with a status opens results. |
| A12 | Sync and errors | |
| A13 | New entry: pick a match | A new entry starts here, then opens A8 prefilled. "Fill in the details myself" skips the lookup. |
| A14 | Music by artist, text view | See section 5 |
| A15 | One artist, text view | |
| A16 | View menu | Text, List with covers, Grid with covers for media types and music albums; Text, List with photos, Grid with photos for music artists and songs. The screen behind is dimmed; the chosen view is highlighted and checked. |
| A17 | Music, list with photos | |
| A18 | Music, grid | |
| A19 | One artist, with photos | |
| A20 | Type picked, list with covers | |
| A21 | Type picked, grid with covers | Title on up to two lines, then the year only, never the status ("Not released yet" without a year); music grids show the artist instead. The check badge on the cover's upper-right corner means Done. L4 follows the same rule. |
| A22 | Album details with track ratings | See section 5 |
| A23 | Filter result: Music + Songs is the Music view | For music the kind plays the status segment's part: Music + Songs opens the Music view on Songs ("Show 3 songs"), and Music alone opens it on Artists ("Show 12 music entries"). Music with both kinds, or with a status, opens results. |
| A24 | Filter result: Music + Albums is the Music view | Same as A23, on Albums ("Show 9 albums"). |
| A25 | Released: wheel picker | A sheet with three wheels, Year, Month and Day, and a line that spells the value out ("Year only: 2013", "June 2013", "June 14, 2013"). Month and Day start on "—", so the value can be a year, a year and month, or a full date, matching the three forms of `released`. The Day wheel lists only the days the chosen month has and stays on "—" until a month is picked; a day the new month lacks becomes its last day. The wheels open on the current value, otherwise on the current year, and the year wheel runs from 1800 to five years ahead. Every change applies at once; Done and swiping down just close. Opening and closing without touching a wheel leaves an empty field empty. Clear (shown only while a value is set) empties the field. |
| A27 | Sync conflict banner | The A12 banner for a conflict: "Changed here and on GitHub", "Pick which copy to keep.", Choose opens D17. |
| A28 | One long tag group, full screen | Opened from the group's row in A2, D14 or S9 (section 7). Title is the group ("Authors"), a Done button, a search box ("Search authors"), a count line ("64 authors · 1 selected"), then the tags A to Z under letter headers with the index rail when the list is long (the L1 rule; the letter headers stay whatever the length). A row is the name ("Ursula K. Le Guin": the creator text of an entry that carries the tag, else the tag's words with capitals), "#tag · 9 entries" and a round check. A tap toggles the tag at once in the sheet underneath; Done and back just close. The search matches the name or the tag and hides the rail; no match says 'No author matches "x".'. |
| A26 | Released: type the year | Tapping the chosen year turns the Year wheel into a numeric field for any four-digit year, for anything older than 1800. The month and day stay. |
| L1, L2, L3 | Long list with a jump rail | The rail shows when both hold: the list is at least three screens tall, and it has two sections or more. Then the text and list views get section headers and a rail on the right that jumps to a section. Sections follow the sort: decades for the year orders (Older before 1960, "Not released yet" last for entries without a date), months of the current year and then whole years for newest added, first letters for title order with "#" for digits, letters for music artists (1d), and for the rating order the ratings that exist, 10 down to 1 and then Unrated (the rail says "None" for it, as "Unrated" does not fit). The highlighted rail label follows the scroll position. A short list has neither headers nor rail. |
| L4 | Long grid with fast scroll | Same rule. The grid keeps no headers; a thumb on the right appears while scrolling and can be dragged, and a bubble next to it names the section at the top of the screen. |
| L5 | Filtered results, one type | Removable chips and the count stay put; the rows scroll, grouped by type. Same rule. When every result is of one type, sections follow the sort, headers in that type's color, rail of short labels. |
| L6 | Filtered results, several types | Same rule. One section per type in type order, headers in the type colors, and the rail shows one colored dot per type instead of labels; the current dot is a little larger. A short result list keeps its type headings and no rail. |

### Plans (S row)

A plan is a named list of entries, for example "Halloween 2026". Plans replace the old "seasonal" files and are not tied to seasons.

| ID | Screen | Notes |
|---|---|---|
| S1 | Plan checklist | Grouped by type, in the global type order. Spacing in the mockup is trimmed; use normal row spacing. |
| S2 | Timeline view | Groups by time, not by type: Earlier, Last week, This week, each future single day ("Sat Oct 17"), Later, and Whenever for undated items. Every bucket mixes types, in the global type order inside. Titles wrap to two lines before cutting off. A rail on the left fills up to today. No highlight on the last item. |
| S4 | All entries matching the plan's tags | Add, edit, remove. Keeps the plan header's progress row. |
| S5 | Plans overview | Active plans as cards, then Not started and Finished as rows (see the plan states below). |
| S6 | Settings | Theme, accent color, timeline default, seasonal theme default; a Library source row that opens D6 and a Libri row (name and version) that opens About (D19) |
| S7 | Entry details in a plan, timeline on | Has a "When" row (D2) and a plan note |
| S8 | Entry details in a plan, timeline off | No "When" row |
| S9 | Edit plan | A Started switch under Name and Year (see the plan states below). |
| S10 | New plan | Can copy an existing plan to a new year |
| S11 | Halloween theme | |
| S12 | Christmas theme | |
| S15 | Plans with the sync conflict banner | The same banner as A27 on the plans overview. |

Plan rules:

- A plan has a name, an optional year, linked tags (multi-select from existing tags; an entry matches if it has any of them), a Timeline switch and a Seasonal theme switch. Both switches default to the values in Settings.
- Plan states, from the S9 note: Not started, Active, Finished.
  - Active: the Started switch is on, or the plan's first date has come. When the first date arrives the app turns Started on, so the switch always shows the real state. A plan never goes inactive on its own after its end date.
  - Finished, automatically: the plan has at least one entry and every entry is done or removed from the plan. An empty plan is never Finished. Finishing shows a short "Halloween 2026 finished" message with Undo, which unticks the last item.
  - Ticking an item also turns Started on, so unticking an entry or adding a new one to a Finished plan makes it Active again.
  - Removing an entry from a plan never removes it from the library. There is no separate close action.
  - The Started help text: on, "Active. Stays active after its end date until every entry is done or removed."; off, "Not started. Turns on by itself when the plan's first date comes."
- The plan header is the same on the checklist, the timeline and the "All <plan>" tab (S11 to S14): row 1 is the name (one line, 32, 28 then 24 px, then an ellipsis) and the ⋮ menu; row 2 is the year chip, the progress bar and "X of Y done". The year chip is never next to the title, and its menu opens right below it.
- "When" on a plan item is empty, a single day, or a period.
- Rewatch or re-read is detected automatically: an entry that is already Done when it is added to a plan is a repeat. Its row says Rewatch for movies, shows and anime, Reread for books, Replay for games and Relisten for music.
- Removing an entry from a plan offers "Remove from this plan" or "Delete everywhere" (D4).
- Seasonal theme: an illustrated 88 px strip at the top, an icon by the title, a themed progress marker and a seasonal accent color. Only inside that plan.

### Dialogs and small screens (D row)

| ID | Screen |
|---|---|
| D1 | Sort menu: Newest added, Title A to Z, Year newest first, Year oldest first, Rating highest first (10 down to 1, unrated last, ties by title; albums and songs by their own rating). |
| D2 | When: a day or a period |
| D3 | Plan menu |
| D4 | Remove from plan, or everywhere |
| D5 | Delete plan |
| D6 | Settings: library connection (also its state with the library kept on the phone after D16) |
| D7 | First load |
| D8 | Library home, light theme |
| D9 | New tag: a similar one exists |
| D10 | New tag: confirm and pick a category (ten categories, section 7) |
| D11 | Rating picker |
| D12 | Saving an album when songs from it are saved |
| D13 | Saving a song when its album is saved |
| D14 | Tag picker (section 7) |
| D15 | Disconnect: confirm (section 10b) |
| D16 | Disconnect: keep or delete the library on this phone (section 10b) |
| D17 | Conflict: keep which copy? (section 10b) |
| D18 | Reconnecting to a different file: which library? (section 10b) |
| D19 | About: the app icon, name, version and build, the open-source licenses and the data source credits |

### First run (F row)

The canvas has F1 Splash, F2 Welcome to Libri, F3 Connect GitHub, F4 Pick a branch, F5 Your library file: new or existing, F6 Create a new library, F7 Pick an existing file, F8 All set. They replace the old first-time setup artboard. The step labels read "Step 1 of 4" (F3) to "Step 4 of 4" (F6 or F7).

- F4 (canvas revision of 2026-10-18): after Connect, Libri lists the repo's branches and shows a loading line while it does. The default branch comes first with a "Default" badge and is preselected; the rest follow A to Z, each with when its head was committed ("Updated 2 days ago", in the words of D6 and F7). The step shows even when the repo has one branch. The pick is saved with the connection (`connection.json`) and used for everything after it: F7 lists the files on that branch, F6 creates the file there, and every read and commit goes to it. D6 shows it in a Branch row under Repository. A failed listing says why, with Try again.
- Finishing the first run (F8, "Open Libri") always opens the library home with All picked, whatever was on screen before: the filter and the type are cleared and the app shell starts fresh (`shellSessionProvider`), so a reconnect begun from D6 above the Plans tab lands on the Library tab too.

## 5. Music

- Music is tracked at album level. A single song can also be an entry (`kind: "song"`).
- **A14** has three tabs: Artists (default), Albums, Songs. Albums and Songs are flat lists.
- Every artist with at least one album or song appears in the same list. The row says what is saved: "7 albums", "2 albums, 3 songs", "1 song".
- Sorting ignores a leading "The" but displays the full name. Names starting with a digit go under "#".
- "Various Artists" (today's "Compilations") is pinned at the very end, after Z.
- An alphabet rail on the right jumps to a letter, under the same rule as every long list (L1 to L6: three screens tall, two sections or more). The text and list views get letter headers; the grid has none and uses the fast-scroll thumb with its letter bubble instead.
- **One artist** shows an Albums section, then a Songs section.
- **A song entry** has an optional `album` text field, normally filled in by the lookup, shown as its subtitle ("Bad Music for Bad People · 1981").

### Track ratings (A22)

- Opening an album writes nothing. The track list is fetched from the lookup and cached on the device.
- Rating a track adds it to the album entry's `tracks` list. Clearing the rating removes it. Only rated tracks are stored.
- A rated track is not a song entry. It has a title, a lookup ID and a rating, nothing else.
- The Songs tab lists song entries and rated tracks together, both with the subtitle "Artist · Year": the year the song, or the album it is on, came out. Tapping a rated track opens its album. Plan rows, which also mix artists, use the same "Artist · Year" for songs. On an artist's own screen a song keeps "Album · Year".
- Offline with no cached track list: show the rated tracks and a line saying the full list needs a connection.

### Replace dialogs

- **D12**, saving an album when song entries from it exist: Keep both / Replace songs with album / Cancel. Replacing moves the songs' ratings into the album's `tracks`.
- **D13**, saving a song when its album exists: Keep both / Replace album with this song / Cancel. The dialog says what would be lost.
- A match needs the same artist and the same album (by lookup ID when available, otherwise by title). No album info on the song means no dialog. Nothing is ever merged without asking.

## 6. Views and covers

- Each list can be shown as Text, List with photos, or Grid. The view button sits next to sort/search and opens the menu in A16.
- The choice is remembered per type, and for music per tab. It is stored on the device.
- Artist photos are round. Covers are poster-shaped for movies, shows, books and anime, and square for albums. The games shape is open.
- With the text view chosen, detail screens stay text-only (A15). With a photo view chosen, they show images (A19).
- Long lists (three screens or more, two sections or more) get section headers and a jump rail, or a fast-scroll thumb in the grid; see L1 to L6.

## 7. Tags

- Tags belong to categories, in this order: Genres (movies, shows, books and anime), Game genres, Music genres, Mood (all types), Season, Authors, Directors (also showrunners and anime directors), Studios (game and animation studios), Animation style, Other. Every tag belongs to one category, picked when it is created (D10). A new tag starts on Game genres for a game, Music genres for music and Genres otherwise. Authors, Directors and Studios replaced the one Creators group on 2026-10-16 (canvas revision A2, A28, D10, D14); the data repo's eleven creator tags were sorted by hand (seven authors, four directors) without renaming any.
- A creator tag's group is the person's or studio's main role, not the entry's type: #stephen-king is in Authors even on a movie.
- Within every group, tags are listed A to Z by the tag itself, so people sort by first name (#ray-bradbury under R, #stephen-king under S), and a leading "the" is ignored. The order in `library.json` is not touched: a new tag is still appended, and the sort is a display rule (`lib/features/library/tag_sort.dart`).
- A group of more than 24 tags (typically a creator group) is one row, "Authors · 64 authors · 1 selected ›", that opens the full-screen list A28; shorter groups stay inline chips. While a search is typed, a long group shows its matches inline like any other group. The same row and screen serve A2, D14 and the plan's linked hashtags (S9, S10).
- The creator field suggests its tag (A8, `lib/features/entry/creator_tags.dart`): the author of a book (Authors), the director or showrunner of a movie or show (Directors), the studio of a game or an anime (Studios), as a slug of the name ("Ursula K. Le Guin" is #ursula-k-le-guin, "Jo Nesbø" is #jo-nesbo); several names ("Stephen King & Peter Straub") give several tags. Music suggests nothing, since an artist is not a tag. A tag the library has goes on at once like a matched genre when the entry comes from a lookup; otherwise, and for a tag that does not exist yet, it is offered under the field as a dashed chip (marked "new" when new), and creating it opens D10 on its creator group. The suggestion follows the field as it is edited, but waits until the field is left, so a half-typed name is never offered. Editing an existing entry never adds a tag by itself.
- Studios whose name is how their films are known get the studio's tag instead of the director's: a Pixar film suggests #pixar, not the director; likewise #disney (Walt Disney Animation Studios, Walt Disney Productions, DisneyToon), #dreamworks (DreamWorks Animation) and #studio-ghibli. The studio comes from the lookup's production companies (TMDB), studios (AniList) or developers (IGDB), checked in that order so a Pixar film that also lists Walt Disney Pictures is #pixar; "Walt Disney Pictures" alone is a live-action film and keeps its director. Typed by hand, "Hayao Miyazaki" and "Isao Takahata" still mean #studio-ghibli. The table is `brandStudios` and `houseDirectors` in `creator_tags.dart`.
- Filter sheet (A2): a category group shows only when at least one of its tags is used by an entry of the chosen types. This comes from the library, not a fixed mapping, so Games shows Genres too once a game is tagged #crime, and Studios shows with Movies chosen once a movie carries #pixar. With no type chosen, every group shows. A chosen tag whose group goes away is dropped.
- Tag picker (D14): Game genres only for games and Music genres only for music, unless you search; a search finds any tag. The picker opens without the keyboard, since a tag is usually tapped rather than typed; the search box takes the keyboard on a tap. Plan hashtags (S9, S10) list every category.
- A new tag can only be created from the entry form's tag picker, so every tag is used by at least one entry. A tag that no entry uses disappears.
- Before creating a tag, check for similar existing ones: same when hyphens are ignored; one letter different (two for tags of six letters or more); two neighboring letters swapped; singular versus plural. If one is found, show D9.
- Creating a tag always goes through D10 to confirm it and pick its category.

## 8. Data: `library.json` version 2

```json
{
  "version": 2,
  "tags": { "Genres": ["horror", "scifi"], "Mood": ["lighthearted"] },
  "entries": [
    {
      "id": "movies/the-mummy-1999",
      "type": "movies",
      "title": "The Mummy",
      "released": "1999",
      "creator": "Stephen Sommers",
      "status": "done",
      "rating": 9,
      "tags": ["adventure", "lighthearted", "halloween"],
      "note": "",
      "description": "",
      "seasonal_only": false,
      "added": "2026-10-01",
      "source": null
    }
  ],
  "plans": [
    {
      "id": "halloween-2026",
      "name": "Halloween",
      "year": 2026,
      "tags": ["halloween"],
      "timeline": true,
      "seasonal_theme": true,
      "started": true,
      "items": [
        { "entry": "movies/the-mummy-1999", "done": false, "repeat": true, "note": "", "when": { "from": "2026-10-19", "to": "2026-10-31" } }
      ]
    }
  ]
}
```

Field rules:

- `id`: `<type>/<title>-<year>` for every type but music (`movies/the-mummy-1999`, `books/dracula-1897`), `music/<title>-<artist>` for music (`music/dirt-alice-in-chains`). One scheme for the app and the data: the phase 3 migration assigned every existing id with the app's `EntryId.generate`, so nothing in `ekmanch/library` follows an older rule.
- `type`: `movies`, `shows`, `books`, `games`, `music`, `anime`.
- `released` is text with flexible precision: `"1999"`, `"2026-12"` or `"2026-12-25"`. There is no separate `year`; the app derives the year and whether the title is out yet.
- `creator` is one field; the app labels it Director, Author, Artist and so on by type.
- `status`: `want`, `in_progress`, `done`, `dnf`.
- `rating`: 1 to 10 or `null`.
- `seasonal_only`: true for titles only wanted in season; hidden from the main lists unless "Include seasonal-only" is on.
- `started` on a plan: the Started switch (S9). Always written, `false` by default; set by the user or by the app when the plan's first date arrives, and never cleared by the app.
- `platform` (games) uses spelled-out names, one spelling per platform: "PlayStation 5", not "PS5" (see `lib/data/models/platform_names.dart`).
- `when` on a plan item: `null`, or `from` and `to` (equal for a single day).
- Type-specific fields: `platform` (games), `formats` (books: `audiobook`, `physical`), and for music `kind` (`album` or `song`), `album` (songs, optional), `tracks` (albums, optional: `[{ "title", "id", "rating" }]`).
- `source`: the lookup id the entry was found by (to re-fetch covers and track lists), for example `"tmdb:movie:694"`, or `null`. Always written, right after `added` and before the type-specific fields; `null` for every migrated entry and for entries added by hand. The data repo's validator only checks that it is text or `null`, not its format. The app writes `tmdb:movie:<id>` and `tmdb:tv:<id>` (movies, shows), `anilist:<id>`, `openlibrary:<work id>` (never an edition), `igdb:<id>`, `deezer:album:<id>` and `deezer:track:<id>`; a rated track's `id` is `deezer:track:<id>`. Only a pick in A13 or "Look up again" in A8 sets it; covers and track lists for entries without one are matched on the device and never written back. Changing an entry's type clears it; editing the title never does.

Not in the file: covers, track lists, view choices, theme, sort order. Those are caches or device preferences.

Rules settled during phase 0:

- A partial `released` counts as released only after its period ends: `"2026-12-25"` on that day, `"2026-12"` from 2027-01-01, `"2027"` from 2028-01-01. A game "coming in 2027" stays "Not released yet" all year. No `released` at all counts as released.
- The file is written in one canonical form so that a save is a minimal git diff: two-space indent, one trailing newline, keys in the order of the sample above, entries and plans never reordered by an edit. Common entry fields are always written, including `"rating": null`; the type-specific fields are omitted when absent. Decoding and re-encoding a canonical file gives back the same bytes.
- Entry ids are slugs frozen at creation: lowercase, apostrophes dropped (`salems-lot`, not `salem-s-lot`), diacritics folded to ASCII, runs of other characters become one hyphen; `<type>/<title>-<year>` for every type but music (books too, never the author), or `music/<title>-<artist>`. A collision gets `-2`, `-3`, for every type (`EntryId.generate`, covered by `test/data/models/entry_id_test.dart`). Editing a title never changes the id, so plan items keep pointing at the right entry.
- A tag disappears from `tags` only when no entry **and no plan** uses it, so a new plan tagged `halloween` keeps the tag alive before any entry has it.

Migration from version 1 (`catalog.<type>` plus `seasonal.<season>.<type>.{plans, coming_later, favorites}`; 659 entries, 425 of them music):

- `dropped` becomes `dnf`; `year` becomes `released`.
- Seasonal favorites merge into the entries.
- Plan and "Coming later" rows become `want` entries tagged with their season, plus plan items.
- The artist "Compilations" becomes "Various Artists".
- The Markdown files and PDFs become output generated from the JSON.

## 9. Sync with GitHub

- Show cached data immediately, then check for changes.
- Check on open and resume, on pull-to-refresh, on tab switch if more than 5 minutes have passed, and always right before saving.
- Use conditional requests so an unchanged file costs almost nothing. Always request the raw format, which supports files up to 100 MB.
- The UI updates at once; saving happens in the background.
- Edits made within 2 to 3 seconds are bundled into one commit with a readable message, such as "Mark The Mummy as done".
- On a conflict, fetch the new file and re-apply the pending operations. Operations are small ("set status of X"), so this is safe.
- Offline edits are queued and sent when the connection returns.
- All storage goes through one interface, so the file can later be split per type without touching the UI.

## 10. Lookups and images

| Type | Source |
|---|---|
| Movies, shows | TMDB (needs a read access token) |
| Anime | AniList (no key) |
| Books | Open Library matches the book: first publication year, author, work id, cover, subjects. Google Books only fills in a missing description or cover; a key is optional but without one it shares a small daily quota with everyone. |
| Games | IGDB (a Twitch client id and secret). Steam was dropped: it knows PC titles only and no console platforms. |
| Music details, track lists, covers | Deezer (no key) |
| Artist photos | Deezer |

No scraping. Goodreads has no public API any more. Spotify was ruled out (Premium and a client secret for a development-mode app since February 2026, attribution in the UI, and terms against caching its images); MusicBrainz has no artist photos and slow, patchy covers. Images are cached on the device. See 10c for how it was built.

### Open

- Whether rated tracks need notes (currently: no, make it a song entry instead).
- Not drawn yet: the "Include seasonal-only" switch in A2, the `seasonal_only` switch in A8, the "Rewatch" label on plan rows, the Album / Song switch in A8.

## 10a. Decisions made while building

- Section headers are uppercase, except decades ("1990s", not "1990S").
- The library home's header scrolls with the list (A1, section 3): every body the home shows (All, a type, the music tabs, filtered results, the empty states) is one `CustomScrollView` on one shared controller, with the header as its first slivers, so the rail's offsets are measured from where the rows begin (`SectionedListBody.leadingSlivers`). The count row is a `PinnedSliver` (`lib/widgets/pinned_sliver.dart`, its fixed height in `entry_list_views.dart`); `SectionedListBody.pinnedExtent` keeps the rail under it and makes a rail jump land a section right below it. A rail jump or a thumb drag lands with the scrolling part of the header out of the way. Switching the type or the music tab starts the new list at the top, so the header is back in view; changing the status segment keeps the position.
- A plan header gives the name priority: it shrinks a little to fit on one line, then truncates with "…"; the year chip sits by the progress bar.
- Every search box is the shared `SearchField`: a magnifying glass on the left, one outline (the accent while typing, the field outline at rest), the text inside it, no border on the inner field. That includes the tag searches in A2, D14 and S9.
- Ticking a plan item marks the entry Done and remembers the old status; unticking restores it unless the status changed in between or was Done already.
- Platform chips in the entry form are only the platforms the game came out on (fetched) plus the entry's own; "Other…" adds anything else. Aliases merge into one spelled-out name.
- A sheet is at most 88% of the screen tall, the tag picker 78%, so the screen behind stays in view.
- Segmented controls that do not fit at a large text size keep their full labels and scroll sideways; the filter sheet's status chips share the row by label length and wrap when they do not fit.
- A filter that is only one type, with at most one status (for music, at most one kind), is not a results screen: the home picks that type and its status segment or music tab instead (the L6 note; see A2, A11, A23).
- A filter that matches nothing spells itself out: "No books are both in progress and tagged #christmas. Remove a filter to see more." The empty state's button clears the filters, so the chip row has no "Clear all" then.
- The active plan card's name shrinks a step (20, 18, 16 px) before cutting off, like the plan header. A button label never wraps either: at a large text size "Create tag" beside Cancel shrinks to fit (D10, checked 2026-10-17).
- At a large text size on a small phone, a timeline card puts its type label above the title so the title gets the full width, and the entry form stacks the creator and Released fields so neither is cut.
- D6: "Check for changes" is a two-line row: the label, then "When you open Libri, then every 5 minutes" in the secondary color, left-aligned.
- Label-and-value rows (`SettingRow`) never center their values. A block of several related details gets a left-aligned value column: the labels sit in a fixed 120 dp column and every value starts 12 dp after it, with a long value wrapping within its column, like the GitHub rows of D6 (Repository, Branch, Data file, Access token; canvas revision of 2026-10-18). A single row gets its value on the right, like Library source and the version row in Settings (S6).
- D2: the range band is drawn per week row from the center of the start day to the center of the end day (to the row edge where the range carries on), 40 px tall, square ends hidden under the dots; no band for a single day.
- The "+" button changes with the screen: on a plan it opens the pool or adds a tagged entry, and wears the plan's seasonal accent.
- Desktop builds use the same visual density as the phone, so Linux captures match the device.
- Settings (S6) also has the default game platform from the canvas (PC, PlayStation 5, Xbox Series X|S, Switch 2, Steam Deck, None). A new game from a lookup starts with it picked when the game came out on it, as the A8 note says.
- The A12 banner sits under the title on both top-level screens, Library and Plans, so a failed save is seen wherever you are.
- Disconnect in D6 is two steps (D15, D16). D15 confirms ("Disconnect from GitHub?", "Libri stops syncing with owner/repo.", "Nothing on GitHub changes."); with changes not yet on GitHub it says they are lost unless the library is kept, and the button reads "Disconnect anyway". D16 asks "Keep your library on this phone?": "Keep it on this phone" (neutral fill) disconnects, keeps `library.json` on the phone and returns to the Library, where it can be browsed and edited without a sync until a repo is connected again; "Delete it from this phone" (destructive) disconnects, deletes `library.json` and opens the first run at the welcome screen (F2); Cancel on either step leaves everything as it was. In both cases the token, the queue and the sync meta leave the phone, GitHub is never touched and display preferences stay. A library kept on the phone is remembered in `connection.json` (`"local": true`); D6 then reads "Not connected", "Your library is kept on this phone", hides the GitHub and Syncing sections and offers "Connect to GitHub", which runs F3 to F8 above the app. Settings shows "Library source: This phone only".
- "Replace token" in D6 opens the Connect GitHub step (F3) on its own, with a Save token button and no step label.
- Phase 2 keeps the library in `library.json` and the display preferences in `preferences.json`, both in a `libri` folder in the app documents directory (never the cache), each written atomically. A new install starts from the bundled fixture until phase 4 connects GitHub. An unreadable library file is renamed aside with an `.unreadable` suffix, never overwritten. Preferences sit behind their own `PreferencesStore`, separate from `LibraryRepository`, and are never synced.
- Every operation has a one-line summary in the imperative ("Mark The Mummy as done", "Tick The Mummy in Halloween 2026"), for the commit messages of phase 4.
- The About version is read from the build (package_info_plus); `lib/app_info.dart` keeps only the name.
- The mark inside the app (F1, F2, D19) is painted in code by `LibriLogo`, so no image is bundled for it. The Android launcher icon is a resource, not a Flutter asset: `android/app/src/main/res/mipmap-*` holds the adaptive layers (background, foreground, monochrome) and the legacy squircle and round PNGs, generated from the masters in `assets/logos/libri/`, which `pubspec.yaml` does not declare. Launchers that theme icons (Android 13's themed icons, Niagara's icon themes) use the monochrome layer where they support it.
- About (D19, canvas revision of 2026-10-18) opens from the Libri row in Settings; both that row and Library source end in a chevron with their values right-aligned. It shows the rectangular app icon, the name, "Version 0.1.0 (build 12)" from the build, an "Open-source licenses" row that opens Flutter's license page, and under Data sources ("Used when you add something, to fetch details and covers.") one row per service Libri actually asks, each opening the service's website in the browser (external-link icon, not a chevron): TMDB, IGDB, Google Books, Open Library, Deezer, AniList. The list is `dataSources` in `lib/features/settings/about_screen.dart` and is the only place a provider is named in the UI. Wikipedia is not a source and is not credited. What each service's terms ask for (checked 2026-10-18): TMDB requires one of their approved logos plus the exact sentence "This product uses the TMDB API but is not endorsed or certified by TMDB." in an About or Credits section (their "Alt short" logo is bundled as `assets/logos/tmdb/tmdb.png`, never redrawn, 13 dp tall so it does not shout); IGDB is free for non-commercial use and asks for visible attribution in a static place only under a commercial partnership; Google Books' branding guidelines ask for Google attribution wherever its content is shown, with "powered by Google" next to search results and a link per book result (Libri shows no Google search results, it only fills in a missing description or cover, so the About row is the credit); Open Library asks nothing (the Internet Archive asserts no rights over the data); Deezer's developer guidelines say every app using the API must show a clearly visible Deezer logo, so the Deezer row carries their 2023 heart-and-wordmark logo from Deezer's own newsroom (`assets/logos/deezer/`, 28 dp tall; the black wordmark on the light theme, the white one on the dark theme); AniList asks nothing beyond its naming rules, which Libri does not touch.
- Phase 3 (the data repo): `library.json` v2 is the source of truth there; `scripts/generate.sh` writes the Markdown lists and tag pages from it, and the GitHub Action commits the regenerated lists after a save from the app. Migrated entries have `rating: null` (favorites keep the `#favorite` tag), `creator: null` outside books and music, `added` from the first commit that listed the title, and plan items keep the old table notes. A wanted entry tagged with a season shows under "Coming later" in that season's list only while its release is ahead; a year-only release counts as out in its own year.

## 11. Visual design

Exact values are in `lib/theme/app_theme.dart`.

- Dark graphite theme by default; a light theme with a white background and soft shadows for cards.
- Fonts: Bricolage Grotesque for titles, Figtree for everything else.
- One accent color chosen by the user in Settings, from a Vivid group and a Pastel group. Default: Hot pink. On the light theme a darker "ink" version of the accent is used for accent text, icons and outlines; every ink reaches 4.5:1 on white (the S6 list). Fills stay the same on both themes.
- Each type has its own color per theme, used for section headings, chip dots, rail dots and labels. The light colors reach 4.5:1 on white, except Movies (3.8:1, kept on purpose so gold stays gold). Values are in the theme file and the D8 note.
- Seasonal accents: Halloween orange, Christmas green, only inside a themed plan.
- Phone frame in the mockups is 390 × 844. The target phone, the Galaxy S25 (1080 × 2340 at 480 dpi), is 360 × 780 dp, and the Linux dev window and the captures use that size. Side padding is 20 px. Touch targets are at least 48 dp: bottom navigation items and segments are 48 dp tall and every segment at least 48 dp wide; 40 dp chips keep their drawn size but get a 48 dp touch area.

## 10b. Sync, as built in phase 4

- Files on the device, in the `libri` folder: `library.json` (the cache of the file on GitHub, in the canonical form), `pending.json` (the operations not yet on GitHub, each with its summary), `sync.json` (the base: which file it is about, the ETag, the blob sha of the remote file, the sha of its canonical re-encoding, the last commit, when the phone last matched GitHub and when it last asked), `connection.json` (repo, file, branch, and whether the library was kept on the phone) and `preferences.json`. The token is in the phone's secure storage only. Disconnect removes `pending.json` and the token; deleting the library in D16 removes `library.json` and `sync.json` too, keeping it leaves both for the comparison on a reconnect.
- An edit goes into `pending.json` before the cache applies it, and leaves it only after the commit that carries it succeeds. A crash between the two never leaves a change in the cache that GitHub will not get.
- Every sync is a three-way comparison against the base in `sync.json`, the file as it was when both sides last matched. The phone's copy is compared by the blob sha of its canonical encoding against the base's canonical sha (so a file formatted by hand on GitHub does not look edited), GitHub's file by its blob sha against the base's blob sha (so commits that touch other files never count). Neither changed: nothing to do. Only the phone: push, with the queue's summaries as the message, or "Save the changes made on this phone" when nothing is queued (edits made while the library was kept on the phone, or an app update that encodes differently). Only GitHub: pull. Both: a conflict (`SyncPhase.conflict`); nothing moves until the user picks a side, "Keep mine" (the phone's copy replaces GitHub's, whatever is there by then) or "Keep GitHub's" (its copy replaces the phone's and the queue is dropped). The banner (A27 on the Library, S15 on Plans) reads "Changed here and on GitHub · Pick which copy to keep." with Choose; D6 shows the same title with "Pick which copy to keep" and Choose in place of Sync now. D17 opens from both: two muted lines ("This phone: N changes", or "edited here" when the edits were made without a queue; "GitHub: last commit Oct 13, 20:12", looked up when the conflict is found), one warning ("Whichever you keep, the other copy's changes are gone. Earlier versions stay in the repo's history."), then Keep mine (neutral fill), Keep GitHub's (destructive) and Decide later (text: closes, the banner stays, nothing syncs until a choice).
- Reconnecting a library kept on the phone to the same repo, file and branch runs that comparison, so edits made on the phone meanwhile are pushed. A base written for another file is no base. Picking another file in F7 while a library is kept on the phone asks D18 ("Which library do you want to keep?", with the entry counts of both): "This phone's" commits the phone's library over the chosen file ("Replace with the library from this phone") before connecting, "The one on GitHub" connects as before so GitHub's copy replaces the phone's, Cancel goes back to F6. Picking the kept library's own file asks nothing: the sync compares both copies to their base. "Create a new library" (F6) with a kept library creates the file from that library, no question asked; F6 and F8 say so.
- The data repo's `library.json` re-encodes to byte-identical output through the app's codec (verified 2026-10-14 against blob `fcc0e42`: same bytes, LF endings, one trailing newline, no `\u` escapes). The repo's pre-commit hook and `scripts/generate.sh` never write `library.json`; only the app does, or careful hand edits, which the canonical sha absorbs.
- Reads use the raw media type (works to 100 MB). Its ETag is the quoted blob sha, checked live, so a save sets the ETag too and the next check is one conditional request. Writes use the Contents API PUT with the blob sha of the file being replaced, computed locally from the raw bytes (`gitBlobSha`); a 1.9 MB file was saved and read back whole in the live test, so there is no 1 MB limit to work around. The data repo's Action commits regenerated Markdown after every save; that moves the branch but not the file's blob, so nothing in the app looks at the branch head.
- A save whose answer was lost (a kill, a dropped connection) is settled before anything is sent again: `pending.json` records the operations, the blob sha and the message of the save in flight. On the next check, the remote file with that sha means it landed; the old sha means it did not; anything else is looked up in the file's last five commits by message. Nothing is saved twice.
- Checks happen on load, when the app comes to the foreground, every 5 minutes while it stays there, on a tab switch when the last check is older than that, on pull-to-refresh on the library home (A1) and the plans overview (S5), and always right before a save. Edits are gathered for 2.5 seconds, then sent as one commit: one operation gives its summary, several give "<first summary> and N other changes" with every summary listed in the body. A save refused for a stale sha (409 or 422) is checked again rather than retried: if GitHub's file changed since the base, that is a conflict; if not (a spurious refusal), the queue goes out on the next round. A save whose answer was lost and turns out to have landed under later changes moves the base to that save, so the later changes are pulled as GitHub's alone.
- The "Saving" banner shows only while the commit is in flight, not during the 2.5 seconds. A 403 with the rate limit used up (or a 429) is a retryable failure ("Could not save", Retry), not a token problem; 401 and other 403s are. A fine-grained token answers 404 for a repo it cannot see, so F3 says "Repository not found, or the token cannot see it". F3 also refuses a token that can read but not write, before the first save.
- A missing or unreadable token at start means the first run, with the last repo and file prefilled in F3. F4 lists up to 100 branches (one page) and asks for each head commit's date in parallel, since the branches endpoint carries none. F7 opens at most 20 JSON files of at most 20 MB from the repo tree to tell libraries from other JSON, and shows each library's entry count and last commit. F6 never overwrites an existing file.
- A 404 from GitHub during a check or a save (the file, the branch or the repo deleted, or a fine-grained token that no longer sees the repo) is `SyncPhase.notFound`, not a failed save: Retry could not help. Two more calls (the repo, then the file's commits on the branch) tell which part is gone, and the banner reads "Library not found on GitHub" with "library.json is gone from owner/repo on main." (or "The branch main is gone from owner/repo.", or "owner/repo is gone, or the token no longer sees it.") and "Nothing syncs until you reconnect."; Fix opens D6, whose status card says the same. Edits keep queuing on the phone and the checks go on, so a restored file or branch syncs again by itself; otherwise Disconnect keeping the library, then connect again (D18 offers to put the phone's copy over another file). The dev switch `SYNC_BANNER=missing` shows the banner.
- The FIRST_RUN dev switch, the widget tests and the screenshot walks talk to an in-memory fake repo (`lib/dev/fake_github_api.dart`) with the canvas's three branches and three files (the files are the same on every branch). The opt-in live test (`test/data/github/github_live_test.dart`, with `LIBRI_LIVE_TOKEN` in the environment) runs against the private scratch repo `ekmanch/libri-scratch`, seeded with a copy of the real `library.json`, in a file it removes at the end. `ekmanch/library` is never touched from the tests.

## 10c. Lookups and images, as built in phase 5

- Keys: copy `secrets.example.json` to `secrets.json` (git-ignored) and run with `flutter run --dart-define-from-file=secrets.json`. `TMDB_READ_TOKEN`, `IGDB_CLIENT_ID` and `IGDB_CLIENT_SECRET` are needed for their types; `GOOGLE_BOOKS_KEY` is optional. A missing key leaves that provider "not set up": nothing is asked and nothing crashes. The IGDB token Twitch issues is kept in `igdb_token.json` under the cache folder and fetched again a day before it expires or when IGDB refuses it. No provider is named anywhere in the UI except on About (D19), where every source is credited.
- A13: typing pauses for 400 ms, then every configured source for the chosen type is asked (on All, every type in parallel, five per type, taking turns in type order; one type gets its source's ten). A thin accent line under the chips shows while a lookup is pending or in flight; refining a query keeps the rows on screen. States: `Looking up "Carrie"…` with a spinner before the first answer; `Is it one of these?` and the rows; `No matches among games.` (a type picked) or `No matches for "Carrie".` (All); `Could not reach the lookup. Check your connection and try again.` with Try again when every source was offline; `The lookup did not answer. Try again in a moment.` with Try again for anything else; `Lookups for games are not set up on this build (no API key).` or `Lookups are not set up on this build (no API keys).`; and `Some lookups could not be reached.` under the rows when only some failed. "Fill in the details myself" stays below in every state. A complete answer is remembered for the session, so switching the type chips back and forth costs nothing.
- Picking a row fetches the full details first (a spinner replaces the chevron): TMDB's search has no director or genres, so they come with the pick; Deezer's has no release date or genres; Open Library's has no description, and Google Books fills that in when Open Library has none. Should that fetch fail, the form opens with what the search had. The form then carries the lookup id into `source`, the released date in full where the provider has it, the description with HTML stripped, the platforms the game came out on (IGDB's "PC (Microsoft Windows)" reads as "PC"), and up to six tag suggestions. A suggested genre first goes through the alias table in `lib/features/entry/similar_tags.dart`, so "Science Fiction" and "sci-fi" become the library's `scifi` and are never offered as new tags beside it; Open Library's catalog notes and pseudo-subjects (`award:hugo_award=1960`, anything long, with punctuation or over three words) are not suggested at all.
- "Look up again" (A8): an outline row at the top of the form whenever no match is applied (an edit of any entry, or a new entry filled in by hand) opens A13 on the entry's type and title in a pick mode without the "Fill in" footer. A pick sets `source`, fills in only the fields the form has empty (creator, released, description, album), adds the platforms as chips, offers the tag suggestions, and shows the "Details fetched online" card. The owner's own text is never overwritten. Saving writes the whole entry as before, and the entry's device-matched cover is forgotten so the next look resolves through the source.
- Covers and photos are shown only in the photo views, and in A6, A22, S7 and S8 when that type's view is a photo view; a text view fetches nothing. `CoverImage` and `ArtistPhoto` in `lib/widgets/` draw the old placeholder (the colored box with the title, the disc with the initials) until the image is on the device and decoded, then the image, decoded at the shown width; a fresh download fades in over 200 ms. The details header's cover carries the title as its screen reader name; covers in rows are skipped by the screen reader, since the row names the title. Covers keep their slots: 2:3 posters for movies, shows, books, anime and games (IGDB's 3:4 art is cropped a little top and bottom), squares for albums and songs, discs for artists.
- Finding a cover: an entry with a `source` asks that provider for its cover (never a search). One without is matched on the device: title and year for movies, shows, books, games and anime (the same title in the same year, else a year off, else, with edition notes like "(2022 Remaster)" set aside, the same again; a different title is never taken), album title and artist for albums, and the album for a song. Books match through Open Library only. The result goes into `artwork.json` under the cache folder: per entry the cover URL and the id it was matched to, keyed to the title, year, creator, album and source at the time, so an edit to any of those means a new lookup. A miss is tried again after fourteen days; offline, rate limited and not set up are not recorded and are tried again next time. Artist photos come from Deezer by exact name ("Various Artists" and "Unknown artist" never ask) and are recorded by name. At most two lookups run at once, in the order the rows asked, with each provider's own gap (AniList two seconds, Open Library half a second, IGDB 300 ms, Deezer 120 ms, TMDB 50 ms); a row that scrolls away before its turn is released. A photo-view scroll over fifty anime therefore takes about two minutes to fill the first time.
- Image files live under `<cache>/libri/images/<sha1 of the url>.img`, one download per URL however many rows ask at once; a failed download is not retried for six hours (thirty seconds when offline). Track lists live under `<cache>/libri/tracks/<album id>.json`. Once per session, fifteen seconds after the library first loads, the records, image files and track lists of entries and artists that are gone are removed; A13 thumbnails go with them at the next start.
- A22: the track list comes from the album's `source`, or from the Deezer album its cover was matched to, through `/album/{id}/tracks`, and is kept on the device; opening an album writes nothing to the library. While it loads the rated tracks show with `Loading the track list…`; offline with nothing cached, `The full track list needs a connection.`; when the source has no list (or no album could be matched), `No track list was found for this album.`; with no rated track the line starts `No tracks rated yet.`. A stored rating is matched to a listed track by id when one matches, else by title with case, punctuation and edition notes set aside, so the ratings written under earlier ids (the fixture's `mb:` ones) still show against a Deezer list. A first rating stores `deezer:track:<id>`; re-rating keeps the stored id. Nothing retries a failed load by itself; opening the album again asks again.
- D13 matches the song's album by its lookup id when the picked song carries one and an album entry has it, else by artist and album title as before. D12 keeps the name rule (song entries do not store their album's id).
- Dev and tests: `lib/dev/fake_lookup.dart` answers every type from a fixed catalog, matches any title with a drawn cover (`lib/dev/fake_images.dart` paints a PNG per URL; no bundled assets), serves two track lists and a photo per artist; `fakeLookupOverrides()` puts it, a temporary cache folder and in-memory records into every widget test, the screenshot walks and the accessibility audit, with latency, a failure or "not configured" on request. The FIRST_RUN dev switch uses the same fake. `LIBRI_LIVE_LOOKUPS=1 flutter test test/data/lookup/lookup_live_test.dart` asks the real providers (AniList, Open Library and Deezer always; TMDB and IGDB with their keys in the environment).

