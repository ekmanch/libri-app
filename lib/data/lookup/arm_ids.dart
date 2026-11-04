import 'package:http/http.dart' as http;

import '../net/http_transport.dart';
import 'http_lookup_source.dart';
import 'rate_limiter.dart';

/// What ARM knows of an AniList entry (section 10c): the TMDB show it is
/// on, the TVDB show and, for a seasonal anime, the TVDB season it is;
/// null for a long run that is one TVDB season list of its own (Hunter x
/// Hunter, One Piece). [tmdb] is a lookup id, `tmdb:tv:46298`.
typedef ArmRow = ({String? tmdb, int? tvdb, int? tvdbSeason});

/// ARM (arm.haglund.dev), the community map between the anime databases:
/// one request per AniList id answers which TMDB show and which TVDB
/// season the entry is (owner's decision, 2026-11-04: 16 of 16 right where
/// a title match missed Hunter x Hunter). No key. A map is kept on the
/// phone by [AniListSource] once made; the title match stands in when ARM
/// has no row or cannot answer.
class ArmIds with LookupHttp {
  ArmIds(
    this.client, {
    Uri? baseUrl,
    this.timeout = defaultHttpTimeout,
    this.userAgent = 'Libri',
  }) : _baseUrl = baseUrl ?? Uri.https('arm.haglund.dev', '/api/v2/ids'),
       limiter = RateLimiter(const Duration(milliseconds: 500));

  @override
  final http.Client client;
  @override
  final Duration timeout;
  @override
  final String userAgent;
  @override
  final RateLimiter limiter;

  final Uri _baseUrl;

  /// ARM's row for the AniList entry [anilistId]; null when it has none
  /// (ARM answers `null`, or 404). Throws for anything else.
  Future<ArmRow?> lookup(int anilistId) async {
    final response = await send(
      () => client.get(
        _baseUrl.replace(
          queryParameters: {'source': 'anilist', 'id': '$anilistId'},
        ),
        headers: {'Accept': 'application/json', 'User-Agent': userAgent},
      ),
    );
    if (response.statusCode == 404) return null;
    check(response);
    final json = decode(response);
    if (json is! Map<String, Object?>) return null;
    final tmdb = json['themoviedb'];
    return (
      tmdb: tmdb is num ? 'tmdb:tv:${tmdb.toInt()}' : null,
      tvdb: (json['thetvdb'] as num?)?.toInt(),
      tvdbSeason: (json['thetvdb-season'] as num?)?.toInt(),
    );
  }
}
