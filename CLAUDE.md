# Libri

Phone-first Flutter app (Android, Samsung Galaxy S25; a Linux desktop build may come later) that is the front end for my personal media library: movies, shows, books, games, music and anime. The data lives in a separate private GitHub repo, `ekmanch/library`, as `library.json`.

## Read these first

- `docs/DESIGN.md`: every settled product and design decision, the screen list, the data format and the sync rules. This is the source of truth. If code and DESIGN.md disagree, ask me.
- `design/canvas.html`: the exported design canvas with all mockups. It holds seven screens: Library, Add / edit entry, Show & seasons, Music, Plans, Settings and First run. Sheets, dialogs and menus open on top of their screen, and each mockup is a named state of a screen, picked with "Start at" in Screen settings. DESIGN.md, TODO.md and the code refer to them as "Screen › state" (Library › Filter sheet, Plans › Plan menu), or by the screen name alone for the whole screen. Older commits use retired codes (A1, D14, F3…); the map from codes to names is in commit a9d7816 (`git show a9d7816:design/screen-map.md`).
- `TODO.md`: the build order. Work through it top to bottom unless I say otherwise.
- `lib/theme/app_theme.dart`: colors, fonts and the theme extension. Never hard-code a color or font in a widget; add it to the theme instead.

## Git rules

- **Never commit, amend, push, tag or create a branch unless I explicitly ask for it in that message.** Finishing a task is not a request to commit. A general instruction earlier in the conversation is not one either.
- When a task is done, end your reply with a **suggested commit message** in a code block so I can use it myself.
- When I have asked for commits, commit a step only after its formatter, analyzer and tests have passed: chain the checks and the commit with `&&`, never `;`, and never commit on a pipeline whose exit status comes from `tail` or `grep` (use `set -o pipefail` or check the test command's own status). A commit that lands over failing tests must not happen.
- Commit message style: `type(scope): Subject (phase N)`. The type is one of feat, fix, doc, test, asset, git, chore; the scope names the area or file; the subject is short and imperative with no trailing period; the phase is the TODO.md phase the work belongs to, with its letter where there is one, e.g. `feat(music): Add artist list with alphabet rail (phase 1d)`. One logical change per commit. Prefer a single line with no body. When one line cannot make the change clear (for example a commit that bundles several fixes), add a brief body of a few sentences, never more. Wrap body lines at 72 characters at most, with a blank line between the header and the body; the header may run longer.
- Never touch the `ekmanch/library` data repo from this project except through the app's own sync code, and never during development unless I ask. Use the fixture file for testing.
- Phases 0 and 1 never write to the data repo. Switching `ekmanch/library` from Markdown to JSON as the source of truth, including reversing its pre-commit hook so Markdown is generated from JSON, happens on a feature branch in that repo at the start of the wiring phase (TODO.md phase 3), and not before.

## Working rules

- Tick off items in `TODO.md` as they are completed. Add new items there when you find missing work, instead of doing unplanned work silently.
- Phase 1 is UI only, on fixture data. Do not add networking, GitHub access or file writing before the phase that calls for it.
- Linux desktop is a dev and test target only, not a shipping platform. Use it for `flutter test integration_test -d linux`; never add Linux-only features.
- To look at a screen, run `flutter test integration_test/screenshots_test.dart -d linux`; it writes PNGs to `screenshots/` (git-ignored) from inside the app. Never capture the desktop with a system screenshot tool.
- The fixture is small. To try long lists (the jump rail and the grid's fast scroll) on a device, run with `--dart-define=LONG_LISTS=true`; `lib/dev/long_lists.dart` then pads every type with generated entries. Development only, never on by default.
- States that nothing produces yet can be forced for a look: `--dart-define=FIRST_RUN=true` starts at the splash and the First run screen, and `--dart-define=SYNC_BANNER=saving|offline|failed|token` shows that banner (Library › Sync and errors). Both live in `lib/dev/demo_states.dart`. Development only, never on by default.
- The lookups need API keys: copy `secrets.example.json` to `secrets.json`, fill it in, and run with `--dart-define-from-file=secrets.json`. `secrets.json` is git-ignored and never committed. Without it, movies, shows and games say their lookup is not set up; AniList, Open Library and Deezer need no key. The tests and walks never need keys: they use the fake in `lib/dev/fake_lookup.dart`.
- Verifying a screen: capture it at the phone's 360 × 780 dp (the Linux window is set to that size) and again at text scale 1.3 (the `large-text-` captures in `screenshots_test.dart`). The mockups are drawn at 390 × 844, so compare proportions, not pixels. Every screen, sheet and dialog gets a capture when it is built. Before calling a phase done, have a subagent that did not write the code compare each capture with its mockup state in `design/canvas.html` and list the differences.
- UI that repeats across screens (search box, chips, buttons, rows) is one shared widget in `lib/widgets/`, never copied.
- Ask before adding a package. Say what it is for and what the alternative is.
- Ask before changing anything that DESIGN.md marks as settled. Proposals are welcome; silent changes are not.
- UI text uses American spelling ("color", "favorite") and sentence case.
- Test in proportion to the change. For a fix or a small feature, first work out what the change could plausibly break: the code it touches, what calls that code, and the screens that show it. Then check only that: run the test files for those areas (for example `flutter test test/features/library/`), capture only the affected screens (one walk with `--plain-name`, e.g. `flutter test integration_test/screenshots_test.dart -d linux --plain-name "library screens in dark and light"`), and look only at those captures. Say in the reply what you checked and why that was enough. Do not rerun every walk, the sizes walk or the accessibility audit for a local change.
- The full pass runs at the end of a phase, and when a change reaches every screen (the theme, a widely used widget in `lib/widgets/`, the models, the codec or the repository): all of `flutter test`, every screenshot walk at 360 and at 1.3, the sizes walk, the accessibility audit, and the subagent review of the captures against the mockups.
- Always run the formatter and the analyzer before saying a task is done (they are fast and catch breakage anywhere), plus the tests chosen above, and tell me if any of them fail:

```bash
dart format .
```

```bash
flutter analyze
```

```bash
flutter test test/features/library/  # The affected areas; plain `flutter test` for a full pass.
```

## Code conventions

- State management: Riverpod. Navigation: Flutter's built-in Navigator; no routing package unless I ask.
- Feature-first folders: `lib/features/<feature>/` with widgets and state together; shared widgets in `lib/widgets/`; models in `lib/data/models/`.
- All reading and writing of the library goes through one `LibraryRepository` interface. Phase 1 uses a fixture implementation; the GitHub implementation comes later. Widgets never know which one they have.
- Models are immutable, built with freezed and json_serializable. The generated `*.freezed.dart` and `*.g.dart` files are committed so the repo builds without a generation step; after changing a model run `dart run build_runner build` and commit the output.
- Every change to the library is expressed as a small operation ("set status", "add entry", "rate track") so it can be re-applied after a sync conflict. Operations never reorder existing entries or plans.
- All `library.json` text goes through `lib/data/library_codec.dart`, so that a save produces a minimal git diff. After editing the fixture by hand, run `dart run tool/format_fixture.dart` to restore the canonical form.
- Display preferences (theme, accent, view per type, sort) are stored on the device, never in `library.json`.
- Touch targets are at least 48 dp (40 dp chips get a 48 dp touch area; see `lib/widgets/touch_target.dart`). Every icon-only button has a tooltip or semantic label.
- Write widget tests for anything with logic (filtering, sorting, similar-tag check, replace dialogs) and unit tests for the models and operations.
- Write a widget test for each screen as it is built, not in a later pass.
