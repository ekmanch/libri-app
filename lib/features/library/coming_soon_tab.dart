/// The three tabs of Library › Coming soon (Coming soon: Library tab,
/// Coming soon: Discover tab, Coming soon: All tab). The one last picked is
/// remembered on the device, like the page's view.
enum ComingSoonTab {
  /// What the owner wants: the home's Coming soon list with no cap, plus the
  /// Want entries without a date. The default, since the page is reached
  /// from the home's list of the owner's own.
  library('Library'),

  /// What is coming that the owner has not asked for, each row to add.
  discover('Discover'),

  /// Both.
  all('All');

  const ComingSoonTab(this.label);

  final String label;
}
