import '../models/released.dart';

/// One episode of a season, as the lookup returns it (A39, A40). [title]
/// is null while the lookup has none ("Title TBA"), [aired] while it has
/// no air date, and [runtime] (minutes) while it has no length. Kept on
/// the phone only, never in `library.json`.
typedef EpisodeInfo = ({
  int number,
  String? title,
  Released? aired,
  int? runtime,
});
