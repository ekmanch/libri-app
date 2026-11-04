import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/arm_ids.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';

void main() {
  late List<http.Request> sent;

  ArmIds arm(Object? body, {int status = 200}) {
    sent = [];
    return ArmIds(
      MockClient((request) async {
        sent.add(request);
        return http.Response(
          body is String ? body : jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  test('asks by AniList id and reads the TMDB show and TVDB season', () async {
    final row = await arm({
      'anilist': 182255,
      'themoviedb': 209867,
      'themoviedb-season': 1,
      'thetvdb': 424536,
      'thetvdb-season': 2,
    }).lookup(182255);
    expect(row, (tmdb: 'tmdb:tv:209867', tvdb: 424536, tvdbSeason: 2));
    expect(sent.single.url.host, 'arm.haglund.dev');
    expect(sent.single.url.queryParameters, {
      'source': 'anilist',
      'id': '182255',
    });
  });

  test('a long run has no season; a missing show is null', () async {
    final row = await arm({
      'themoviedb': 46298,
      'thetvdb': 252322,
      'thetvdb-season': null,
    }).lookup(11061);
    expect(row, (tmdb: 'tmdb:tv:46298', tvdb: 252322, tvdbSeason: null));
    final bare = await arm({'thetvdb': 1}).lookup(2);
    expect(bare!.tmdb, isNull);
  });

  test('no row is null: ARM answers null, or 404', () async {
    expect(await arm('null').lookup(49999999), isNull);
    expect(await arm({'message': 'no'}, status: 404).lookup(3), isNull);
  });

  test('other failures throw', () async {
    await expectLater(
      arm({'message': 'bad'}, status: 400).lookup(999999999),
      throwsA(
        isA<LookupException>().having(
          (e) => e.failure,
          'failure',
          LookupFailure.other,
        ),
      ),
    );
    await expectLater(
      arm('', status: 429).lookup(1),
      throwsA(
        isA<LookupException>().having(
          (e) => e.failure,
          'failure',
          LookupFailure.rateLimited,
        ),
      ),
    );
  });
}
