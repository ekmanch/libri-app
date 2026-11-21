import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/artwork_providers.dart';
import 'package:library_app/data/images/large_cover_providers.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/dev/fake_covers.dart';
import 'package:library_app/dev/fake_images.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/widgets/artist_photo.dart';
import 'package:library_app/widgets/cached_image.dart';
import 'package:library_app/widgets/cover_image.dart';
import 'package:library_app/widgets/cover_placeholder.dart';

import '../helpers/pump_app.dart';
import '../helpers/sample_library.dart';

/// Lets the resolver, the fake fetcher and the file write run (they work
/// off the real clock) until an image is in the tree, or 2 seconds pass.
Future<void> settleImages(WidgetTester tester) async {
  for (var i = 0; i < 40 && find.byType(Image).evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('shows the placeholder, then the fetched cover', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(child: CoverImage(entry: mummy, width: 60)),
      ),
    );
    expect(find.byType(CoverPlaceholder), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await settleImages(tester);
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 60);
    expect(image.height, 90);
    expect(image.excludeFromSemantics, isTrue);

    // Decoded, the cover replaces the placeholder.
    for (
      var i = 0;
      i < 40 && find.byType(CoverPlaceholder).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(CoverPlaceholder), findsNothing);
  });

  testWidgets('a cover that cannot be fetched keeps the placeholder', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(child: CoverImage(entry: mummy, width: 60)),
      ),
      lookupOverrides: fakeLookupOverrides(
        failingImages: {'fake://cover/poster/fake:the-mummy'},
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.byType(CoverPlaceholder), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the details header names its cover', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(child: CoverImage(entry: mummy, width: 84, labeled: true)),
      ),
    );
    await settleImages(tester);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.semanticLabel, 'The Mummy');
    expect(image.excludeFromSemantics, isFalse);
  });

  testWidgets('an artist without a file shows a cover from the library, '
      'round; one with nothing saved the initials', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Column(
          children: [
            ArtistPhoto(name: 'Alice in Chains', initials: 'AC', size: 48),
            ArtistPhoto(name: 'Nobody Saved', initials: 'NS', size: 48),
          ],
        ),
      ),
    );
    expect(find.text('AC'), findsOneWidget);
    expect(find.text('NS'), findsOneWidget);
    await settleImages(tester);
    expect(find.byType(ClipOval), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('NS'), findsOneWidget);
    // The artist's own album, never the music source's artist photo.
    final shown = tester
        .widgetList<CachedImage>(find.byType(CachedImage))
        .map((image) => image.url);
    expect(shown.first, startsWith('fake://cover/square/'));
    expect(shown.first, isNot(contains('artist:')));
    expect(shown.last, isNull);
  });

  testWidgets('the artist\'s file in the library repo comes first, keyed by '
      'its blob so a replaced photo is drawn anew', (tester) async {
    final store = fakeCoverStore(
      files: {'artists/alice-in-chains.jpg': fakeCoverPng('a', square: true)},
    );
    await store.refresh();
    await pumpApp(
      tester,
      const Scaffold(
        body: ArtistPhoto(name: 'Alice in Chains', initials: 'AC', size: 48),
      ),
      overrides: [coverStoreProvider.overrideWithValue(store)],
    );
    CachedImage image() => tester.widget<CachedImage>(find.byType(CachedImage));
    expect(image().url, 'repo:artists/alice-in-chains.jpg');
    final before = image().key;

    await tester.runAsync(
      () => store.putArtistPhoto(
        'Alice in Chains',
        fakeCoverPng('b', square: true),
        picked: true,
        summary: 'Set the photo of Alice in Chains',
      ),
    );
    await tester.pump();
    expect(image().url, 'repo:artists/alice-in-chains.jpg');
    expect(image().key, isNot(before));

    // Use automatic: back to a cover from the library.
    await tester.runAsync(
      () => store.removeArtistPhoto('Alice in Chains', summary: 'Remove'),
    );
    await tester.pump();
    await settleImages(tester);
    expect(image().url, startsWith('fake://cover/square/'));
  });
  group('the larger version', () {
    const small = 'fake://cover/poster/x';
    const larger = 'fake://cover/poster/x-larger';

    Widget cover({String? largeUrl = larger}) => Scaffold(
      body: Center(
        child: CachedImage(
          url: small,
          largeUrl: largeUrl,
          width: 240,
          height: 360,
          placeholder: const SizedBox(),
        ),
      ),
    );

    Future<void> settle(WidgetTester tester, int images) async {
      for (
        var i = 0;
        i < 40 && find.byType(Image).evaluate().length < images;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
    }

    testWidgets('is fetched when the cover is opened, into its own folder, '
        'and drawn over the image the lists show', (tester) async {
      final container = await pumpApp(tester, cover());
      await settle(tester, 2);
      expect(find.byType(Image), findsNWidgets(2));
      final fetcher = container.read(imageFetcherProvider) as FakeImageFetcher;
      expect(fetcher.fetched, containsAll([small, larger]));
      final store = container.read(largeImageCacheProvider);
      expect(store.cachedFile(larger), isNotNull);
      expect(store.cachedFile(larger)!.path, contains('images_large'));
      expect(container.read(imageCacheProvider).cachedFile(larger), isNull);
    });

    testWidgets('that cannot be fetched leaves the smaller image, with no '
        'error', (tester) async {
      await pumpApp(
        tester,
        cover(),
        lookupOverrides: fakeLookupOverrides(failingImages: {larger}),
      );
      await settle(tester, 2);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is never asked for by a list', (tester) async {
      final container = await pumpApp(tester, cover(largeUrl: null));
      await settle(tester, 2);
      expect(find.byType(Image), findsOneWidget);
      final fetcher = container.read(imageFetcherProvider) as FakeImageFetcher;
      expect(fetcher.fetched, [small]);
    });
  });
}
