import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/media_type.dart';
import '../music/music_tab.dart';
import 'home_type_provider.dart';
import 'library_filter.dart';

/// The filter applied on the library home. Session state, not a preference.
class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() {
    // What narrows a type's own view belongs to that type: another type
    // picked or swiped to lets go of it.
    ref.listen(homeTypeProvider, (previous, next) {
      if (state.types.length == 1 && state.types.single != next) {
        state = LibraryFilter.none;
      }
    });
    return LibraryFilter.none;
  }

  void set(LibraryFilter filter) => _apply(filter);

  /// Clears every filter, the type included, so the home shows All.
  void clear() => _apply(LibraryFilter.none);

  void remove(ActiveFilterChip chip) => _apply(chip.remove(state));

  /// Narrows the list of the type shown in place, with [filter] naming that
  /// type: a tag picked or lifted in the Tags row. The status chip and the
  /// music tab stay as they are.
  void narrow(LibraryFilter filter) => state = filter.narrowing;

  /// The home's type follows the filter: one type picks it, none or several
  /// pick All. A filter that names one type is never a results screen: the
  /// home shows that type's view, with its status chip or music tab picked
  /// when the filter has one status or kind (Library › Movies + Done (filter
  /// result); Music: songs (filter result); Music: albums (filter result)),
  /// and what is left of the filter ([LibraryFilter.narrowing]) stays here
  /// and narrows that list in place. The type's own chip or tab follows; the
  /// other types keep theirs.
  void _apply(LibraryFilter filter) {
    final view = filter.typeView;
    state = filter.narrowing;
    ref.read(homeTypeProvider.notifier).set(view?.type);
    if (view == null) return;
    if (view.type == MediaType.music) {
      ref.read(homeMusicTabProvider.notifier).set(MusicTab.forKind(view.kind));
    } else {
      ref.read(homeStatusProvider.notifier).set(view.type, view.status);
    }
  }
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilter>(
      LibraryFilterNotifier.new,
    );
