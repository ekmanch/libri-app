import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/tag_category.dart';

import '../../helpers/pump_app.dart';

void main() {
  test('Actors sits between Directors and Studios', () {
    final order = TagCategory.values;
    expect(
      order.indexOf(TagCategory.actors),
      order.indexOf(TagCategory.directors) + 1,
    );
    expect(
      order.indexOf(TagCategory.studios),
      order.indexOf(TagCategory.actors) + 1,
    );
  });

  test('Actors is written as "Actors", in category order', () {
    final fixture = loadFixture();
    final text = encodeLibrary(
      fixture.copyWith(
        tags: {
          ...fixture.tags,
          TagCategory.actors: ['kate-siegel'],
        },
      ),
    );
    expect(text, contains('"Actors": [\n'));
    expect(text.indexOf('"Actors"'), greaterThan(text.indexOf('"Season"')));
    expect(text.indexOf('"Actors"'), lessThan(text.indexOf('"Studios"')));
    expect(decodeLibrary(text).tags[TagCategory.actors], ['kate-siegel']);
  });

  test('the picker offers Actors to movies and shows only', () {
    for (final type in MediaType.values) {
      expect(
        TagCategory.actors.offeredFor(type),
        type == MediaType.movies || type == MediaType.shows,
        reason: type.name,
      );
    }
    expect(TagCategory.actors.isPeopleGroup, isTrue);
    expect(TagCategory.actors.isCreatorGroup, isFalse);
    expect(TagCategory.studios.isPeopleGroup, isFalse);
  });
}
