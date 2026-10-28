import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'analytics.dart';

final analytics = AppAnalytics(
  const AnalyticsConfig.fromEnvironment(),
  PosthogSink(),
);
final analyticsCollectionEnabled = ValueNotifier(false);

class PosthogSink implements AnalyticsSink {
  @override
  Future<void> setup(AnalyticsConfig config) async {
    // This integration targets the existing mobile app only; no JS/web snippet.
    if (kIsWeb ||
        !const {
          TargetPlatform.iOS,
          TargetPlatform.android,
        }.contains(defaultTargetPlatform)) {
      return;
    }
    await Posthog().setup(buildPosthogConfig(config));
  }

  @override
  Future<void> setEnabled(bool value) async {
    if (value) {
      await Posthog().optIn();
    } else {
      await Posthog().optOut();
    }
  }

  @override
  Future<void> capture(String name, Map<String, Object> properties) =>
      Posthog().capture(eventName: name, properties: properties);
}

@visibleForTesting
PostHogConfig buildPosthogConfig(AnalyticsConfig config) =>
    PostHogConfig(config.token)
      ..host = config.host
      ..optOut = true
      ..debug = false
      ..personProfiles = PostHogPersonProfiles.never
      ..captureApplicationLifecycleEvents = false
      ..sessionReplay = false
      ..surveys = false
      ..preloadFeatureFlags = false
      ..sendFeatureFlagEvent = false
      ..capturePushNotificationSubscriptions = false
      ..capturePushNotificationOpened = false
      ..rageClickConfig.enabled = false
      ..logsConfig.beforeSend = [(_) => null];
