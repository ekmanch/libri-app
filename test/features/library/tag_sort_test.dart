import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/features/library/tag_sort.dart';

import '../../helpers/sample_library.dart';

void main() {
  test('tags sort A to Z by the tag itself, so people by first name', () {
    expect(sortedTags(['stephen-king', 'ray-bradbury', 'dan-simmons']), [
      'dan-simmons',
      'ray-bradbury',
      'stephen-king',
    ]);
  });

  test('a leading "the" is ignored', () {
    expect(sortedTags(['the-cramps', 'alice-in-chains', 'the-cure', 'zz']), [
      'alice-in-chains',
      'the-cramps',
      'the-cure',
      'zz',
    ]);
    expect(tagSortKey('the-cramps'), 'cramps');
    expect(tagSortKey('theory'), 'theory');
  });

  test('the display name is the creator text when an entry has it', () {
    final library = Library(
      tags: const {
        TagCategory.authors: ['stephen-king', 'ursula-k-le-guin'],
        TagCategory.directors: ['mike-flanagan'],
      },
      entries: [
        mummy.copyWith(
          id: 'books/left-hand',
          creator: 'Ursula K. Le Guin',
          tags: const ['ursula-k-le-guin'],
        ),
        mummy.copyWith(
          id: 'books/talisman',
          creator: 'Stephen King & Peter Straub',
          tags: const ['stephen-king'],
        ),
        mummy.copyWith(
          id: 'movies/doctor-sleep',
          creator: null,
          tags: const ['mike-flanagan'],
        ),
      ],
    );
    expect(tagDisplayName('ursula-k-le-guin', library), 'Ursula K. Le Guin');
    expect(tagDisplayName('stephen-king', library), 'Stephen King');
    // No creator text carries it: the tag's words with capitals.
    expect(tagDisplayName('mike-flanagan', library), 'Mike Flanagan');
    expect(tagDisplayName('team-cherry', library), 'Team Cherry');
  });

  test('the count label names the group', () {
    expect(
      tagGroupCountLabel(TagCategory.authors, 64, 1),
      '64 authors · 1 selected',
    );
    expect(tagGroupCountLabel(TagCategory.authors, 1, 0), '1 author');
    expect(
      tagGroupCountLabel(TagCategory.studios, 3, 2),
      '3 studios · 2 selected',
    );
    expect(tagGroupCountLabel(TagCategory.actors, 2, 0), '2 actors');
    expect(tagGroupNoun(TagCategory.actors, 1), 'actor');
    expect(tagGroupCountLabel(TagCategory.genre, 30, 0), '30 tags');
    expect(tagGroupNoun(TagCategory.directors, 1), 'director');
  });

  test('splitCreators handles the joins the lookups use', () {
    expect(splitCreators('Craig Mazin, Neil Druckmann'), [
      'Craig Mazin',
      'Neil Druckmann',
    ]);
    expect(splitCreators('Stephen King & Peter Straub'), [
      'Stephen King',
      'Peter Straub',
    ]);
    expect(splitCreators('Simon and Garfunkel'), ['Simon', 'Garfunkel']);
    expect(splitCreators('Brandon Sanderson'), ['Brandon Sanderson']);
  });
}
