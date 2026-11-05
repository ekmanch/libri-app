import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry_status.dart';
import '../../data/models/media_type.dart';
import '../../widgets/labels.dart';
import '../music/music_tab.dart';

/// The type chip picked on the library home (Library › Home); null means All.
/// Shared with the shell so the "+" button can say what it adds. A swipe
/// between the types writes it when the pages come to rest.
class HomeTypeNotifier extends Notifier<MediaType?> {
  @override
  MediaType? build() => null;

  void set(MediaType? type) => state = type;
}

final homeTypeProvider = NotifierProvider<HomeTypeNotifier, MediaType?>(
  HomeTypeNotifier.new,
);

/// The status segment of each type's view (Library › Movies, text view); a
/// type that is not here is on All. Each type keeps its own, so swiping away
/// and back finds the segment as it was left; a return to the home clears
/// them all.
class HomeStatusNotifier extends Notifier<Map<MediaType, EntryStatus>> {
  @override
  Map<MediaType, EntryStatus> build() => const {};

  void set(MediaType type, EntryStatus? status) => state = {
    for (final MapEntry(:key, :value) in state.entries)
      if (key != type) key: value,
    type: ?status,
  };

  void clear() => state = const {};
}

final homeStatusProvider =
    NotifierProvider<HomeStatusNotifier, Map<MediaType, EntryStatus>>(
      HomeStatusNotifier.new,
    );

/// The tab of the Music view (Library › Music: artists, text view). Kept
/// while another type is shown; a return to the home goes back to Artists.
class HomeMusicTabNotifier extends Notifier<MusicTab> {
  @override
  MusicTab build() => MusicTab.artists;

  void set(MusicTab tab) => state = tab;
}

final homeMusicTabProvider = NotifierProvider<HomeMusicTabNotifier, MusicTab>(
  HomeMusicTabNotifier.new,
);

/// The "+" button's label on the Library tab: "New entry" on All, otherwise
/// "New movie", "New album or song".
String newEntryLabel(MediaType? type) => switch (type) {
  null => 'New entry',
  MediaType.music => 'New album or song',
  _ => 'New ${type.singular.toLowerCase()}',
};
