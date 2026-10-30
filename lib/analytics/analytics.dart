import 'dart:async';

/// Only these compile-time values configure analytics. Missing/invalid = no-op.
class AnalyticsConfig {
  const AnalyticsConfig({
    required this.token,
    required this.host,
    required this.environment,
  });
  const AnalyticsConfig.fromEnvironment()
    : token = const String.fromEnvironment('POSTHOG_PROJECT_TOKEN'),
      host = const String.fromEnvironment('POSTHOG_HOST'),
      environment = const String.fromEnvironment(
        'POSTHOG_ENVIRONMENT',
        defaultValue: 'development',
      );
  final String token, host, environment;
  bool get valid {
    final uri = Uri.tryParse(host);
    return token.startsWith('phc_') &&
        token.length > 4 &&
        const {
          'development',
          'testflight',
          'production',
        }.contains(environment) &&
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (uri.path.isEmpty || uri.path == '/');
  }
}

abstract interface class AnalyticsSink {
  Future<void> setup(AnalyticsConfig config);
  Future<void> setEnabled(bool value);
  Future<void> capture(String name, Map<String, Object> properties);
  Future<String?> installId(); // 지금 설치 식별자(삭제 요청 메일에 적는다)
  Future<void> resetInstallId(); // 새 임의 식별자로 바꾼다(이전 기록과 끊는다)
}

/// Typed entry points deliberately cannot accept body, title, translation or email.
/// All SDK work is detached from navigation; failures are contained here.
class AppAnalytics {
  AppAnalytics(this.config, this.sink, {int Function()? elapsedMilliseconds})
    : _elapsed =
          elapsedMilliseconds ??
          (Stopwatch()..start()).elapsedMillisecondsGetter;
  final AnalyticsConfig config;
  final AnalyticsSink sink;
  final int Function() _elapsed;
  bool _enabled = false, _ready = false, _initialized = false, _active = false;
  int _generation = 0;
  Future<void> _consentWork = Future<void>.value();
  (String, String?)? _route;
  final _loadedReaders = <String>{};
  int? _readingSince;
  bool get enabled => _enabled;
  bool get configured => config.valid;

  void setEnabled(bool enabled) {
    _enabled = enabled && configured;
    _generation++;
    _ready = false;
    _readingSince = null; // Never send a pre-consent or revoked interval.
    final generation = _generation;
    _consentWork = _consentWork
        .then((_) async {
          if (!_initialized && _enabled) {
            await sink.setup(config);
            _initialized = true;
          }
          if (!_initialized) return;
          await sink.setEnabled(_enabled);
          if (generation != _generation || !_enabled) return;
          _ready = true;
          _startReading();
          if (_active) _send('app_foregrounded');
          final route = _route;
          if (route != null) _screen(route);
        })
        .catchError((Object _) {
          _ready = false;
          // No exception text is logged or forwarded; app functionality is independent.
        });
  }

  /// 「분석 데이터 삭제 요청」: 수집을 끄고 설치 식별자를 새로 바꾼다. 이전 식별자를 돌려줘 삭제 요청 메일에 적는다.
  /// 한 번도 수집을 켜지 않아 SDK를 시작하지 않은 설치는 보낸 기록이 없으므로 null.
  Future<String?> forgetInstall() {
    _enabled = false;
    _generation++;
    _ready = false;
    _readingSince = null;
    // SDK를 시작한 적 없으면 보낸 기록도 없다: 앞선 동의 작업을 기다리지 않고 바로 끝낸다
    if (!_initialized) return Future.value(null);
    final done = Completer<String?>();
    _consentWork = _consentWork
        .then((_) async {
          if (!_initialized) return done.complete(null);
          await sink.setEnabled(false);
          final id = await sink.installId();
          await sink.resetInstallId();
          done.complete(id);
        })
        .catchError((Object _) {
          if (!done.isCompleted) done.complete(null);
        });
    return done.future;
  }

  void _send(String name, [Map<String, Object> properties = const {}]) {
    if (!_enabled || !_ready) return;
    // Native capture queues synchronously via the platform channel; never await in UI.
    unawaited(
      _capture(name, {
        ...properties,
        r'$geoip_disable': true,
        'environment': config.environment,
        'schema_version': 1,
      }),
    );
  }

  Future<void> _capture(String name, Map<String, Object> properties) async {
    try {
      await sink.capture(name, properties);
    } catch (_) {
      // Offline, missing plugin, SDK errors must not interrupt any app operation.
    }
  }

  static String? _contentId(String? id) =>
      id != null &&
          id.length <= 120 &&
          RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._/-]*$').hasMatch(id)
      ? id
      : null;
  Map<String, Object> _id(String? id) {
    final safe = _contentId(id);
    return safe == null ? {} : {'content_id': safe};
  }

  void bookmark(String id, String kind, bool added, {bool restored = false}) {
    if (!const {'paper', 'news', 'model'}.contains(kind)) return;
    _send(added ? 'bookmark_added' : 'bookmark_removed', {
      ..._id(id),
      'content_kind': kind,
      if (restored) 'restored': true,
    });
  }

  void category(String? code) {
    if (code != null &&
        !const {'llm', 'agent', 'multimodal', 'optimization'}.contains(code)) {
      return;
    }
    _send('category_selected', {
      'category': code ?? 'all',
      'scope': 'paper_topic',
    });
  }

  void termOpened({required bool highlighted, required bool hasTranslation}) =>
      _send('term_opened', {
        'highlighted': highlighted,
        'has_translation': hasTranslation,
      });

  /// Router delegate gives the visible branch, including push/pop and deep links.
  /// Query strings, unknown routes, date values and raw URLs are never sent.
  void navigation(Uri uri, {int exploreTab = 0, bool updates = false}) {
    final p = uri.pathSegments;
    (String, String?)? next;
    if (p.length == 1) {
      final screen = switch (p[0]) {
        'home' => 'home',
        'library' => 'library',
        'settings' => 'settings',
        'explore' => switch (exploreTab) {
          1 => updates ? 'explore_updates' : 'explore_news',
          2 => 'explore_models',
          _ => 'explore_papers',
        },
        _ => null,
      };
      if (screen != null) next = (screen, null);
    } else if (p.length == 2 && p[0] == 'explore') {
      next = ('digest_archive', null);
    } else if (p.length == 2 &&
        p[0] == 'settings' &&
        const {'reading', 'source', 'privacy', 'notices'}.contains(p[1])) {
      next = ('settings_${p[1]}', null);
    } else if (p.length == 2 &&
        const {'paper', 'news', 'model'}.contains(p[0])) {
      next = ('${p[0]}_detail', _contentId(p[1]));
    } else if (p.length == 3 && p[0] == 'paper' && p[2] == 'reader') {
      next = ('paper_reader', _contentId(p[1]));
    }
    if (next == _route) return;
    _flushReading('navigation');
    _route = next;
    _startReading();
    if (next != null) _screen(next);
  }

  void _screen((String, String?) route) {
    _send(r'$screen', {r'$screen_name': route.$1});
    final event = switch (route.$1) {
      'paper_detail' => 'paper_opened',
      'news_detail' => 'official_news_opened',
      'model_detail' => 'model_opened',
      'paper_reader' => 'reader_opened',
      _ => null,
    };
    if (event != null) _send(event, _id(route.$2));
    if (route.$1.startsWith('explore_')) {
      _send('category_selected', {
        'scope': 'explore',
        'category': route.$1.substring(8),
      });
    }
  }

  void readerLoaded(String id) {
    _loadedReaders.add(id);
    _startReading();
  }

  void readerDisposed(String id) {
    _flushReading('navigation');
    _loadedReaders.remove(id);
  }

  void setActive(bool active) {
    if (_active == active) return;
    if (!active) _flushReading('background');
    _active = active;
    if (active) {
      _send('app_foregrounded');
      _startReading();
    }
  }

  void _startReading() {
    final route = _route;
    if (_readingSince == null &&
        _enabled &&
        _ready &&
        _active &&
        route?.$1 == 'paper_reader' &&
        _loadedReaders.contains(route?.$2)) {
      _readingSince = _elapsed();
    }
  }

  void checkpoint() {
    _flushReading('checkpoint');
    _startReading();
  }

  void _flushReading(String reason) {
    final since = _readingSince;
    _readingSince = null;
    if (since == null) return;
    final duration = _elapsed() - since;
    if (duration > 0) {
      _send('reader_active_time', {
        ..._id(_route?.$2),
        'active_ms': duration,
        'reason': reason,
      });
    }
  }
}

extension on Stopwatch {
  int elapsedMillisecondsGetter() => elapsedMilliseconds;
}
