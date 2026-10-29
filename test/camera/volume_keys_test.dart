import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/camera/volume_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sonoglitch/volume_keys');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> press() async {
    final reply = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('press')),
      (_) => reply.complete(),
    );
    await reply.future;
  }

  test(
    'fake channel gates presses and releases interception on disposal',
    () async {
      final source = MethodChannelVolumeKeys(channel: channel);
      var presses = 0;
      final subscription = source.presses.listen((_) => presses++);
      await press();
      expect(presses, 0);
      source.enabled = true;
      source.enabled = true;
      await press();
      await press();
      expect(presses, 2);
      source.enabled = false;
      await press();
      expect(presses, 2);
      source.enabled = true;
      source.dispose();
      source.dispose();
      source.enabled = true;
      await subscription.cancel();
      expect(calls.map((call) => call.method), everyElement('setEnabled'));
      expect(calls.map((call) => call.arguments), [true, false, true, false]);
    },
  );

  test('no-op does not contact Android', () async {
    const source = NoopVolumeKeys();
    source.enabled = true;
    expect(await source.presses.toList(), isEmpty);
    source.dispose();
    expect(calls, isEmpty);
  });

  test('only Android selects the native implementation', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final source = platformVolumeKeys();
      expect(
        source is MethodChannelVolumeKeys,
        platform == TargetPlatform.android,
      );
      source.dispose();
    }
  });
}
