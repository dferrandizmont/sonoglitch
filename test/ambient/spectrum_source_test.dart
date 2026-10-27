import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/spectrum_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sonoglitch/spectrum');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> event(Object value) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeSuccessEnvelope(value),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'channel carries only three band scalars and cancels native input',
    () async {
      final readings = <SpectrumBands>[];
      final errors = <Object>[];
      final subscription = const EventChannelSpectrumSource().bands.listen(
        readings.add,
        onError: errors.add,
      );
      await Future<void>.delayed(Duration.zero);
      await event([-10, -30.5, -60]);
      expect(readings, [(bass: -10, mid: -30.5, treble: -60)]);
      await event([1, 2]);
      await event([1, 2, double.nan]);
      await event('audio');
      expect(errors, everyElement(isFormatException));
      expect(errors, hasLength(3));
      await subscription.cancel();
      expect(calls, ['listen', 'cancel']);
    },
  );

  test(
    'unavailable native microphone terminates without producing bands',
    () async {
      final errors = <Object>[];
      final done = Completer<void>();
      final subscription = const EventChannelSpectrumSource().bands.listen(
        (_) => fail('Unavailable input must not produce a band'),
        onError: errors.add,
        onDone: done.complete,
      );
      await Future<void>.delayed(Duration.zero);
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeErrorEnvelope(code: 'unavailable'),
        (_) {},
      );
      await messenger.handlePlatformMessage(channel.name, null, (_) {});
      await done.future;
      expect((errors.single as PlatformException).code, 'unavailable');
      await subscription.cancel();
    },
  );

  test('no-op source opens no native input', () async {
    expect(await const NoopSpectrumSource().bands.toList(), isEmpty);
    expect(calls, isEmpty);
  });
}
