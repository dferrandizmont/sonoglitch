import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_file_type.dart';
import 'package:sonoglitch/export/export_service.dart';
import 'package:sonoglitch/export/image_encoder.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late DebugLog log;
  late MethodChannel channel;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sonoglitch_encoder_');
    log = DebugLog();
    channel = const MethodChannel(ImageEncoder.channelName);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  /// The files of the directory, by extension.
  List<File> filesOf(String extension) => directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith(extension))
      .toList();

  test('the PNG is the default and every type has its own extension', () {
    expect(ExportFileType.png.extension, '.png');
    expect(ExportFileType.jpeg.extension, '.jpg');
  });

  test('the PNG is written as it is', () async {
    final service = ExportService(log: log, temporaryDirectory: directory);
    final image = await buildFlatTestImage(width: 8, height: 8);
    addTearDown(image.dispose);

    final file = await service.writeFile(image, ExportFileType.png);

    expect(file.path.endsWith('.png'), isTrue);
    expect(file.existsSync(), isTrue);
    expect(filesOf('.png'), hasLength(1));
  });

  test('the JPEG is encoded by the plugin and the PNG is deleted', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final arguments = call.arguments as Map<Object?, Object?>;
          final output = arguments['outputPath']! as String;
          File(output).writeAsStringSync('jpeg');
          return output;
        });
    final service = ExportService(log: log, temporaryDirectory: directory);
    final image = await buildFlatTestImage(width: 8, height: 8);
    addTearDown(image.dispose);

    final file = await service.writeFile(image, ExportFileType.jpeg);

    expect(calls, hasLength(1));
    expect(calls.single.method, ImageEncoder.encodeMethod);
    expect(
      (calls.single.arguments as Map<Object?, Object?>)['inputPath'],
      isA<String>(),
    );
    expect(file.path.endsWith('.jpg'), isTrue);
    expect(file.readAsStringSync(), 'jpeg');
    expect(
      filesOf('.png'),
      isEmpty,
      reason: 'The intermediate PNG is deleted when the JPEG is written',
    );
    expect(filesOf('.jpg'), hasLength(1));
  });

  test(
    'a partial JPEG is removed and the PNG is kept when encoding fails',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final arguments = call.arguments as Map<Object?, Object?>;
            final output = File(arguments['outputPath']! as String);
            output.writeAsStringSync('partial jpeg');
            expect(output.existsSync(), isTrue);
            throw PlatformException(code: 'encode_failed');
          });
      final service = ExportService(log: log, temporaryDirectory: directory);
      final image = await buildFlatTestImage(width: 8, height: 8);
      addTearDown(image.dispose);

      final file = await service.writeFile(image, ExportFileType.jpeg);

      expect(file.path.endsWith('.png'), isTrue);
      expect(file.existsSync(), isTrue);
      expect(filesOf('.png'), hasLength(1));
      expect(filesOf('.jpg'), isEmpty);
      expect(
        log.recentLines.join('\n'),
        contains('could not be encoded'),
        reason: 'The fallback is written in the log',
      );
    },
  );

  test('the PNG is kept when the encoder writes no file', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    final service = ExportService(log: log, temporaryDirectory: directory);
    final image = await buildFlatTestImage(width: 8, height: 8);
    addTearDown(image.dispose);

    final file = await service.writeFile(image, ExportFileType.jpeg);

    expect(file.path.endsWith('.png'), isTrue);
    expect(file.existsSync(), isTrue);
  });
}
