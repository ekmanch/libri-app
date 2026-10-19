import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry_status.dart';
import '../../data/models/media_type.dart';
import '../../widgets/labels.dart';
import '../music/music_tab.dart';

/// The type chip picked on the library home (Library › Home); null means All.
/// Shared with the shell so the "+" button can say what it adds.
class HomeTypeNotifier extends Notifier<MediaType?> {
  @override
  MediaType? build() => null;

  void set(MediaType? type) => state = type;
}

final homeTypeProvider = NotifierProvider<HomeTypeNotifier, MediaType?>(
  HomeTypeNotifier.new,
);

/// The status segment of the type view (Library › Movies, text view); null
/// means All. A new type starts on All.
class HomeStatusNotifier extends Notifier<EntryStatus?> {
  @override
  EntryStatus? build() {
    ref.watch(homeTypeProvider);
    return null;
  }

  void set(EntryStatus? status) => state = status;
}

final homeStatusProvider = NotifierProvider<HomeStatusNotifier, EntryStatus?>(
  HomeStatusNotifier.new,
);

/// The tab of the Music view (Library › Music: artists, text view). A new type
/// starts on Artists.
class HomeMusicTabNotifier extends Notifier<MusicTab> {
  @override
  MusicTab build() {
    ref.watch(homeTypeProvider);
    return MusicTab.artists;
  }

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
