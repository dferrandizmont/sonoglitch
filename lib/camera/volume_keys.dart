import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Intercepts Android volume keys only while the viewfinder can take a photo.
abstract interface class VolumeKeys {
  set enabled(bool value);
  Stream<void> get presses;
  void dispose();
}

class MethodChannelVolumeKeys implements VolumeKeys {
  MethodChannelVolumeKeys({
    this.channel = const MethodChannel('sonoglitch/volume_keys'),
  }) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'press' && _enabled && !_disposed) {
        _presses.add(null);
      }
    });
  }

  final MethodChannel channel;
  final _presses = StreamController<void>.broadcast(sync: true);
  bool _enabled = false;
  bool _disposed = false;

  @override
  Stream<void> get presses => _presses.stream;

  @override
  set enabled(bool value) {
    if (_disposed || _enabled == value) return;
    _enabled = value;
    unawaited(_sendEnabled(value));
  }

  Future<void> _sendEnabled(bool value) async {
    try {
      await channel.invokeMethod<void>('setEnabled', value);
    } on MissingPluginException {
      // Tests and older hosts may not provide the Android channel.
    } on PlatformException {
      // Hardware shortcuts must never prevent the on-screen shutter working.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    enabled = false;
    _disposed = true;
    channel.setMethodCallHandler(null);
    unawaited(_presses.close());
  }
}

class NoopVolumeKeys implements VolumeKeys {
  const NoopVolumeKeys();

  @override
  set enabled(bool value) {}

  @override
  Stream<void> get presses => const Stream.empty();

  @override
  void dispose() {}
}

VolumeKeys platformVolumeKeys() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? MethodChannelVolumeKeys()
    : const NoopVolumeKeys();
