import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/http_lookup_source.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/rate_limiter.dart';
import 'package:library_app/data/models/media_type.dart';

/// The smallest HTTP source: one GET, checked, with pauses short enough
/// for a test.
class _Source extends HttpLookupSource {
  _Source(super.client) : super(minGap: Duration.zero);

  @override
  String get id => 'test';

  @override
  Set<MediaType> get types => const {MediaType.movies};

  @override
  Duration get backoffBase => const Duration(milliseconds: 40);

  @override
  Duration get maxBackoff => const Duration(milliseconds: 500);

  Future<int> get() async {
    final response = await send(() => client.get(Uri.https('x.test', '/')));
    check(response);
    return response.statusCode;
  }

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async => const [];

  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) async => null;

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async =>
      null;
}

void main() {
  test(
    'a 429 is sent again after a pause, twice, then is rate limited',
    () async {
      var calls = 0;
      final times = <DateTime>[];
      final source = _Source(
        MockClient((_) async {
          calls++;
          times.add(DateTime.now());
          return calls < 3 ? http.Response('', 429) : http.Response('{}', 200);
        }),
      );
      expect(await source.get(), 200);
      expect(calls, 3);
      // 40 ms, then 80 ms (doubling), give or take the scheduler.
      expect(
        times[1].difference(times[0]).inMilliseconds,
        greaterThanOrEqualTo(35),
      );
      expect(
        times[2].difference(times[1]).inMilliseconds,
        greaterThanOrEqualTo(75),
      );

      calls = 0;
      final refused = _Source(
        MockClient((_) async {
          calls++;
          return http.Response('', 429);
        }),
      );
      await expectLater(
        refused.get(),
        throwsA(
          isA<LookupException>().having(
            (e) => e.failure,
            'failure',
            LookupFailure.rateLimited,
          ),
        ),
      );
      expect(calls, 3, reason: 'the request and two retries, no more');
    },
  );

  test('Retry-After is honored in seconds; a pause beyond the limit is not waited for', () async {
    var calls = 0;
    final source = _Source(
      MockClient((_) async {
        calls++;
        return http.Response('', 429, headers: {'retry-after': '3600'});
      }),
    );
    final started = DateTime.now();
    await expectLater(source.get(), throwsA(isA<LookupException>()));
    expect(calls, 1);
    expect(DateTime.now().difference(started).inSeconds, lessThan(2));
    expect(
      LookupHttp.retryAfter(
        http.Response('', 429, headers: {'retry-after': '7'}),
      ),
      const Duration(seconds: 7),
    );
    expect(
      LookupHttp.retryAfter(
        http.Response(
          '',
          429,
          headers: {'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT'},
        ),
      ),
      isNull,
    );
  });

  test(
    'the hold applies to the whole source, not just the refused request',
    () async {
      var clock = DateTime(2026, 10, 30, 9);
      final limiter = RateLimiter(Duration.zero, now: () => clock);
      final order = <String>[];
      // Held for 60 ms (real time: the limiter waits by the wall clock it is
      // given, so move it along as the pause passes).
      limiter.holdFor(const Duration(milliseconds: 60));
      final a = limiter.run(() async => order.add('a'));
      final b = limiter.run(() async => order.add('b'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(order, isEmpty);
      clock = clock.add(const Duration(milliseconds: 60));
      await Future.wait([a, b]);
      expect(order, ['a', 'b']);
    },
  );
}
