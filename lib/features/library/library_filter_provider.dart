import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../music/music_tab.dart';
import 'home_type_provider.dart';
import 'library_filter.dart';

/// The filter applied on the library home. Session state, not a preference.
class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => LibraryFilter.none;

  void set(LibraryFilter filter) => _apply(filter);

  /// Clears every filter, the type included, so the home shows All.
  void clear() => _apply(LibraryFilter.none);

  void remove(ActiveFilterChip chip) => _apply(chip.remove(state));

  /// The home's type follows the filter: one type picks it, none or several
  /// pick All. A filter the home's chips can show (one type, at most one
  /// status, or for music at most one kind) is not a results screen: it clears
  /// and the home shows that type's view with its status segment or music tab
  /// picked (Library › Movies + Done (filter result); Music: songs (filter
  /// result); Music: albums (filter result)).
  void _apply(LibraryFilter filter) {
    final types = filter.types;
    final view = filter.typeView;
    state = view == null ? filter : LibraryFilter.none;
    ref
        .read(homeTypeProvider.notifier)
        .set(types.length == 1 ? types.single : null);
    ref.read(homeStatusProvider.notifier).set(view?.status);
    ref.read(homeMusicTabProvider.notifier).set(MusicTab.forKind(view?.kind));
  }
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilter>(
      LibraryFilterNotifier.new,
    );
