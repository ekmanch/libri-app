/// Which of a movie's release dates Coming soon and the details show and
/// sort by (Settings › Movies › Release dates; DESIGN.md 10c). The entry's
/// `released` always holds the first release date anywhere, whatever the
/// setting; the setting only picks what is shown. The dates themselves are
/// kept on the device (`MovieDates`).
enum ReleaseDates {
  /// The date the movie opens in cinemas.
  cinema('cinema', 'Cinema'),

  /// The date it can be rented or bought at home; a streaming premiere
  /// counts as digital.
  digital('digital', 'Digital'),

  /// The first date, with both shown in the details and the add sheet
  /// ("In cinemas Dec 18 · Digital Feb 2027"). The default.
  both('both', 'Both');

  const ReleaseDates(this.key, this.label);

  /// The value in `settings.json` (`movies.release_dates`).
  final String key;

  /// The segment's label in Settings.
  final String label;

  static ReleaseDates? byKey(String? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return null;
  }
}
