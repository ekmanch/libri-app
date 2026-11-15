import 'dart:typed_data';

import '../data/covers/artist_photos.dart';
import '../data/lookup/apple_artists.dart';
import '../data/lookup/itunes_books.dart';
import '../data/models/entry_id.dart';
import 'fake_images.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Apple's artists for the widget tests and the walks: nobody is asked.
/// Every artist has a stand-in suggested photo, but those in [noPhoto]
/// (by slug), and "Ghost" has three other artists of the name, as the
/// mockup draws them (Music › Pick a photo: others with the same name).
class FakeAppleArtists extends AppleArtists {
  FakeAppleArtists({this.noPhoto = const {}})
    : super(
        ITunesBooks(
          MockClient((_) async => http.Response('', 404)),
          minGap: Duration.zero,
        ),
        pageGap: Duration.zero,
        pageJitter: Duration.zero,
      );

  /// The slugs of the artists Apple has no photo for.
  final Set<String> noPhoto;

  /// What was asked, in order: "choices:Ghost", "photo:ghost-o1".
  final calls = <String>[];

  static const _otherAlbums = [
    'Ghost in the Machine',
    'Ghost Stories Live',
    'Ghosts of the Past',
  ];

  static String photoUrl(String key) => 'fake://cover/square/artist:$key';

  @override
  Future<ArtistChoices> choices(String name, Iterable<String> owned) async {
    calls.add('choices:$name');
    final slug = slugify(name);
    return (
      suggested: noPhoto.contains(slug) ? null : photoUrl(slug),
      others: [
        if (slug == 'ghost')
          for (final (i, album) in _otherAlbums.indexed)
            (id: 'ghost-o$i', page: 'fake://artist/ghost-o$i', album: album),
      ],
    );
  }

  @override
  Future<String?> photoOf(String id, String page) async {
    calls.add('photo:$id');
    return photoUrl(id);
  }

  @override
  Future<ArtistFound> find(String name, Iterable<String> owned) async {
    calls.add('find:$name');
    final slug = slugify(name);
    return noPhoto.contains(slug)
        ? const ArtistNotFound(MissingReason.noPhoto)
        : ArtistPhotoFound(fakeCoverPng('artist:$slug', square: true));
  }

  @override
  Future<Uint8List> image(String url) async => fakeCoverPng(url, square: true);
}
