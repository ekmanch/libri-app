import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/plan.dart';
import 'package:library_app/data/models/plan_item.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/models/track.dart';

final mummy = Entry(
  id: 'movies/the-mummy-1999',
  type: MediaType.movies,
  title: 'The Mummy',
  released: const Released(1999),
  creator: 'Stephen Sommers',
  status: EntryStatus.done,
  rating: 9,
  tags: const ['adventure', 'lighthearted', 'halloween'],
  added: DateTime(2026, 10, 1),
);

final dirt = Entry(
  id: 'music/dirt-alice-in-chains',
  type: MediaType.music,
  title: 'Dirt',
  released: const Released(1992),
  creator: 'Alice in Chains',
  status: EntryStatus.done,
  rating: 10,
  tags: const ['grunge'],
  added: DateTime(2026, 1, 15),
  kind: EntryKind.album,
  tracks: const [Track(title: 'Rooster', id: 'mb:1', rating: 10)],
);

final halloweenPlan = Plan(
  id: 'halloween-2026',
  name: 'Halloween',
  year: 2026,
  tags: const ['halloween'],
  timeline: true,
  seasonalTheme: true,
  items: [
    PlanItem(
      entry: mummy.id,
      repeat: true,
      when: PlanWhen(from: DateTime(2026, 10, 19), to: DateTime(2026, 10, 31)),
    ),
  ],
);

/// Two entries, one plan, and a tag map where "scifi" is used by nothing
/// and "christmas" is used only by a plan.
Library sampleLibrary() => Library(
  tags: const {
    TagCategory.genre: ['adventure', 'scifi', 'grunge'],
    TagCategory.mood: ['lighthearted'],
    TagCategory.season: ['halloween', 'christmas'],
  },
  entries: [mummy, dirt],
  plans: [
    halloweenPlan,
    const Plan(id: 'christmas-2026', name: 'Christmas', tags: ['christmas']),
  ],
);
