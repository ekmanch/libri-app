import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/features/library/cover_grid_tile.dart';
import 'package:library_app/widgets/cover_placeholder.dart';

import '../../helpers/sample_library.dart';

void main() {
  test('grid captions and placeholder colors', () {
    final today = DateTime(2026);
    // The year only, whatever the status (the Library › Movies, grid with
    // covers note).
    expect(CoverGridTile.yearCaption(mummy, today: today), '1999');
    expect(
      CoverGridTile.yearCaption(
        mummy.copyWith(status: EntryStatus.want),
        today: today,
      ),
      '1999',
    );
    expect(
      CoverGridTile.yearCaption(
        mummy.copyWith(status: EntryStatus.want, released: null),
        today: today,
      ),
      '',
    );
    expect(
      CoverPlaceholder.paletteIndex('The Mummy', 4),
      CoverPlaceholder.paletteIndex('The Mummy', 4),
    );
    expect(CoverPlaceholder.aspectRatio(MediaType.music), 1);
    expect(
      CoverPlaceholder.aspectRatio(MediaType.movies),
      closeTo(2 / 3, 1e-9),
    );
  });
}
