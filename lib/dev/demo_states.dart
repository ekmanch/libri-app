// Development switches for states that nothing in phase 1 produces on its
// own. Never on by default.
//
//   flutter run --dart-define=FIRST_RUN=true
//       starts at the splash and the first-run flow (F1 to F8).
//   flutter run --dart-define=SYNC_BANNER=saving|offline|failed|token|expired|conflict|missing
//       shows that A12 banner on the Library and Plans screens.
//   flutter run --dart-define=TOKEN_EXPIRES_IN=6
//       the token expires in that many days, so D20 shows at start
//       (0 for "today"; 7 or more is outside the warning window).

/// Start with the first-run flow instead of the library.
const firstRunDemo = bool.fromEnvironment('FIRST_RUN');

/// Which sync banner to show at start; empty for none.
const syncBannerDemo = String.fromEnvironment('SYNC_BANNER');

/// In how many days the token expires, for D20; negative for no demo.
const tokenExpiresInDemo = int.fromEnvironment(
  'TOKEN_EXPIRES_IN',
  defaultValue: -1,
);
