import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rootgist/analytics/analytics.dart';
import 'package:rootgist/analytics/posthog_sink.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

class MemorySink implements AnalyticsSink {
  final events = <(String, Map<String, Object>)>[];
  final consent = <bool>[];
  Completer<void>? setupGate;
  bool fail = false;
  int setups = 0;
  @override
  Future<void> setup(AnalyticsConfig config) async {
    setups++;
    if (fail) throw StateError('offline');
    await setupGate?.future;
  }

  @override
  Future<void> setEnabled(bool value) async {
    consent.add(value);
  }

  @override
  Future<void> capture(String name, Map<String, Object> properties) async {
    if (fail) throw StateError('offline');
    events.add((name, properties));
  }
}

const config = AnalyticsConfig(
  token: 'phc_test',
  host: 'https://eu.i.posthog.com',
  environment: 'testflight',
);
Future<void> drain() => Future<void>.delayed(Duration.zero);

void main() {
  test('official SDK starts opted out without replay, profiles, auto events, surveys or exceptions', () {
    final c = buildPosthogConfig(config);
    expect(c.projectToken, 'phc_test');
    expect(c.host, 'https://eu.i.posthog.com');
    expect(c.optOut, true);
    expect(c.sessionReplay, false);
    expect(c.captureApplicationLifecycleEvents, false);
    expect(c.personProfiles, PostHogPersonProfiles.never);
    expect(c.surveys, false);
    expect(c.preloadFeatureFlags, false);
    expect(c.capturePushNotificationOpened, false);
    expect(c.capturePushNotificationSubscriptions, false);
    expect(c.errorTrackingConfig.captureFlutterErrors, false);
    expect(c.errorTrackingConfig.captureNativeCrashes, false);
    expect(c.errorTrackingConfig.capturePlatformDispatcherErrors, false);
  });
  test(
    'capture failure after setup does not escape or stop later navigation',
    () async {
      final sink = MemorySink();
      final a = AppAnalytics(config, sink)..setEnabled(true);
      await drain();
      sink.fail = true;
      a.navigation(Uri.parse('/home'));
      await drain();
      sink.fail = false;
      a.navigation(Uri.parse('/library'));
      await drain();
      expect(sink.events.last.$2[r'$screen_name'], 'library');
    },
  );

  test(
    'missing token, unsafe host and unrecognized environment disable analytics',
    () {
      expect(
        const AnalyticsConfig(
          token: '',
          host: '',
          environment: 'development',
        ).valid,
        false,
      );
      expect(
        const AnalyticsConfig(
          token: 'phc_test',
          host: 'http://example.com',
          environment: 'testflight',
        ).valid,
        false,
      );
      expect(
        const AnalyticsConfig(
          token: 'phc_test',
          host: 'https://user:password@host',
          environment: 'testflight',
        ).valid,
        false,
      );
      expect(
        const AnalyticsConfig(
          token: 'phc_test',
          host: 'https://host/?email=x',
          environment: 'testflight',
        ).valid,
        false,
      );
      expect(
        const AnalyticsConfig(
          token: 'phc_test',
          host: 'https://host',
          environment: 'typo',
        ).valid,
        false,
      );
      expect(
        const AnalyticsConfig(
          token: 'phx_private',
          host: 'https://eu.i.posthog.com',
          environment: 'testflight',
        ).valid,
        false,
      );
      expect(config.valid, true);
    },
  );
  test('no consent means no setup or events; revocation during setup drops pending events', () async {
    final sink = MemorySink()..setupGate = Completer<void>();
    final a = AppAnalytics(config, sink);
    a.bookmark('1234.56789', 'paper', true);
    expect(sink.setups, 0);
    a.setEnabled(true);
    await drain(); // setup is now actually waiting on the gate
    a.bookmark('1234.56789', 'paper', true);
    a.setEnabled(false);
    sink.setupGate!.complete();
    await drain();
    expect(sink.events, isEmpty);
    expect(sink.consent.last, false);
  });
  test('setup and capture failures are contained; invalid configuration stays inert', () async {
    final sink = MemorySink()..fail = true;
    final a = AppAnalytics(config, sink);
    a.setEnabled(true);
    a.navigation(Uri.parse('/paper/1234.56789'));
    await drain();
    expect(sink.events, isEmpty);
    final invalid = MemorySink();
    AppAnalytics(
      const AnalyticsConfig(token: '', host: '', environment: 'testflight'),
      invalid,
    ).setEnabled(true);
    await drain();
    expect(invalid.setups, 0);
  });
  test('nested routes deduplicate, back opens previous detail, queries and unknown paths never leak', () async {
    final sink = MemorySink();
    final a = AppAnalytics(config, sink)..setEnabled(true);
    await drain();
    sink.events.clear();
    a.navigation(Uri.parse('/paper/1234.56789?email=secret@example.com'));
    a.navigation(Uri.parse('/paper/1234.56789?s=A02'));
    a.navigation(Uri.parse('/paper/1234.56789/reader'));
    a.navigation(Uri.parse('/paper/1234.56789'));
    a.navigation(Uri.parse('/private/secret@example.com'));
    await drain();
    expect(
      sink.events
          .where((e) => e.$1 == '\$screen')
          .map((e) => e.$2['\$screen_name']),
      ['paper_detail', 'paper_reader', 'paper_detail'],
    );
    expect(sink.events.where((e) => e.$1 == 'paper_opened').length, 2);
    expect(sink.events.toString(), isNot(contains('secret')));
    expect(sink.events.every((e) => e.$2['environment'] == 'testflight'), true);
  });
  test('reading excludes loading, inactive time, other routes and opt-out intervals', () async {
    var ms = 0;
    final sink = MemorySink();
    final a = AppAnalytics(config, sink, elapsedMilliseconds: () => ms)
      ..setEnabled(true);
    await drain();
    a.setActive(true);
    a.navigation(Uri.parse('/paper/1234.56789/reader'));
    ms = 5000; // loading: not reading
    a.readerLoaded('1234.56789');
    ms = 7000;
    a.setActive(false);
    ms = 107000;
    a.setActive(true);
    ms = 110000;
    a.navigation(Uri.parse('/settings'));
    ms = 150000;
    a.navigation(Uri.parse('/paper/1234.56789/reader'));
    ms = 151000;
    a.setEnabled(false); // discard current chunk on revocation
    ms = 200000;
    a.setEnabled(true);
    await drain();
    ms = 202000;
    a.checkpoint();
    await drain();
    final times = sink.events
        .where((e) => e.$1 == 'reader_active_time')
        .map((e) => e.$2['active_ms']);
    expect(times, [2000, 3000, 2000]);
  });
  test('payloads allow only content IDs and finite category codes, never term text or URLs', () async {
    final sink = MemorySink();
    final a = AppAnalytics(config, sink)..setEnabled(true);
    await drain();
    sink.events.clear();
    a.bookmark('1234.56789', 'paper', true);
    a.bookmark('https://host/news?email=secret@example.com', 'news', false);
    a.category('llm');
    a.category('secret@example.com');
    a.termOpened(highlighted: true, hasTranslation: true);
    await drain();
    expect(sink.events.map((e) => e.$1), [
      'bookmark_added',
      'bookmark_removed',
      'category_selected',
      'term_opened',
    ]);
    expect(sink.events[1].$2.containsKey('content_id'), false);
    expect(sink.events.toString(), isNot(contains('secret')));
    expect(sink.events[3].$2['highlighted'], true);
  });
}
