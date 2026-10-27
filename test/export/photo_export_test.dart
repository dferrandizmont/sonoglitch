import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/camera/still_source.dart';
import 'package:sonoglitch/debug/capture_timings.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/export/export_capture_timings.dart';
import 'package:sonoglitch/export/export_file_type.dart';
import 'package:sonoglitch/export/export_format.dart';
import 'package:sonoglitch/export/export_layout.dart';
import 'package:sonoglitch/export/export_readings.dart';
import 'package:sonoglitch/export/export_quality.dart';
import 'package:sonoglitch/export/export_service.dart';
import 'package:sonoglitch/export/image_encoder.dart';
import 'package:sonoglitch/export/photo_export.dart';

class Surface extends Fake implements ui.Image {
  Surface(this.width, this.height);
  @override
  final int width;
  @override
  final int height;
  int disposals = 0;
  @override
  void dispose() {
    disposals++;
  }
}

class Source extends StillSource {
  Source(this.width, this.height);
  @override
  final int width;
  @override
  final int height;
  @override
  int compressedBytes = 0;
  final decoded = <Surface>[];
  final sizes = <(int, int)>[];
  int failures = 0;
  Object? error;
  @override
  Future<ui.Image> decode(int width, int height) async {
    sizes.add((width, height));
    if (error != null) throw error!;
    if (failures-- > 0) throw OutOfMemoryError();
    final image = Surface(width, height);
    decoded.add(image);
    return image;
  }
}

class Export extends ExportService {
  Export(this.directory) : super(log: DebugLog());
  final Directory directory;
  final surfaces = <Surface>[];
  final events = <String>[];
  String? fail;
  Object? failure;
  Surface surface(int width, int height) {
    final image = Surface(width, height);
    surfaces.add(image);
    return image;
  }

  void stage(String name) {
    events.add(name);
    if (fail == name) {
      fail = null;
      throw failure ?? StateError('Injected $name failure');
    }
  }

  @override
  Future<ui.Image> crop(ui.Image source, ExportFormat format) async {
    stage('crop');
    final rect = ExportPlan.cropRect(source.width, source.height, format);
    return surface(rect.width.toInt(), rect.height.toInt());
  }

  @override
  Future<ui.Image> compose(
    ui.Image source,
    ExportFormat format, {
    bool watermark = true,
    ExportLayout layout = ExportLayout.full,
    ExportLayoutValues? values,
  }) async {
    stage('compose');
    expect(format, ExportFormat.original);
    final plan = ExportLayoutPlan.build(
      layout: layout,
      photoWidth: source.width,
      photoHeight: source.height,
      readings: hasExportReadings(values),
      context: values?.context?.hasItems ?? false,
      watermark: watermark,
      photoId: values?.photoId,
    );
    return surface(plan.width, plan.height);
  }

  @override
  Future<File> writePng(ui.Image image) async {
    stage('encode');
    return File('${directory.path}/full.png')
      ..writeAsStringSync('${image.width}x${image.height}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Export export;
  late DebugLog log;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('sonoglitch_export_');
    export = Export(directory);
    log = DebugLog();
  });
  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  Future<PhotoExport> process(
    Source source, {
    ExportQuality quality = ExportQuality.maximum,
    ExportFormat format = ExportFormat.original,
    bool Function()? cancelled,
    void Function(int)? onProgress,
    int retainedImageBytes = 0,
  }) =>
      PhotoExporter(
        export: export,
        log: log,
        textureProbe: (_) async => 16384,
      ).process(
        source: source,
        quality: quality,
        format: format,
        watermark: true,
        retainedImageBytes: retainedImageBytes,
        cancelled: cancelled,
        onProgress: onProgress,
        render: (image, maxSide) async {
          export.stage('render');
          expect(
            maxSide,
            image.width > image.height ? image.width : image.height,
          );
          return export.surface(image.width, image.height);
        },
      );

  void released(Source source, PhotoExport result) {
    result.image.dispose();
    for (final image in [...source.decoded, ...export.surfaces]) {
      expect(
        image.disposals,
        1,
        reason: '${image.width}x${image.height} must be disposed exactly once',
      );
    }
  }

  test('native capture keeps 24 MP, crop precedes render, progress and dimensions are reported', () async {
    final source = Source(6000, 4000);
    final pixels = <int>[];
    final result = await process(source, onProgress: pixels.add);
    expect(result.file.readAsStringSync(), '6000x4000');
    expect(pixels, [24000000]);
    expect(export.events, ['crop', 'render', 'compose', 'encode']);
    expect(log.recentLines.last, contains('size=6000x4000'));
    final timings = ExportCaptureTimings(
      const CaptureTimings(takeMs: 12),
      result.metadata,
    );
    expect(timings.toJson()['width'], 6000);
    expect(timings.toJson()['height'], 4000);
    expect(timings.toJson()['takeMs'], 12);
    for (final key in ['decodeMs', 'renderMs', 'encodeMs']) {
      expect(timings.toJson()[key], isA<double>());
    }
    released(source, result);
  });

  test(
    '4:5 crop is applied before the effect, without resizing twice',
    () async {
      final source = Source(6000, 4000);
      final result = await process(source, format: ExportFormat.portrait);
      expect(source.sizes, [(6000, 4000)]);
      expect(result.file.readAsStringSync(), '3200x4000');
      released(source, result);
    },
  );

  for (final stage in ['crop', 'render', 'compose', 'encode']) {
    test(
      '$stage OOM falls back Maximum to High and releases every surface',
      () async {
        final source = Source(6000, 4000);
        export.fail = stage;
        export.failure = OutOfMemoryError();
        final result = await process(source);
        expect(source.sizes, [(6000, 4000), (4096, 2730)]);
        expect(result.metadata['quality'], 'high');
        expect(
          log.recentLines.any((line) => line.contains('maximum -> high')),
          isTrue,
        );
        final diagnostics = log.recentLines.join('\n');
        expect(
          diagnostics,
          contains('quality=maximum stage=$stage retry=true'),
        );
        expect(diagnostics, contains('Out of Memory'));
        expect(diagnostics, contains('Export.stage'));
        expect(diagnostics, contains('quality=high PNG'));
        released(source, result);
      },
    );
  }

  for (final stage in ['crop', 'render', 'compose', 'encode']) {
    for (final failure in [
      StateError('Injected bug reading /private/captures/source.png'),
      FileSystemException('No space left', '/private/captures/source.png'),
      Exception('operation failed'),
    ]) {
      test(
        '$stage ${failure.runtimeType} propagates without fallback',
        () async {
          final source = Source(6000, 4000);
          export.fail = stage;
          export.failure = failure;
          await expectLater(process(source), throwsA(same(failure)));
          expect(source.sizes, [(6000, 4000)]);
          for (final image in [...source.decoded, ...export.surfaces]) {
            expect(image.disposals, 1);
          }
          final diagnostics = log.recentLines.join('\n');
          expect(
            diagnostics,
            contains('quality=maximum stage=$stage retry=false'),
          );
          expect(diagnostics, contains('Export.stage'));
          expect(diagnostics, isNot(contains('/private/captures/')));
          expect(diagnostics, isNot(contains('export fallback')));
        },
      );
    }
  }

  test('decoder bugs propagate with the original error and stack', () async {
    final failure = StateError('Decoder bug');
    final source = Source(6000, 4000)..error = failure;
    await expectLater(process(source), throwsA(same(failure)));
    expect(source.sizes, [(6000, 4000)]);
    final diagnostics = log.recentLines.join('\n');
    expect(diagnostics, contains('stage=decode retry=false'));
    expect(diagnostics, contains('Decoder bug'));
    expect(diagnostics, contains('Source.decode'));
  });

  test('rounded 4:5 export stays below 24 MP without another resize', () async {
    final source = Source(5951, 8402);
    final result = await process(source, format: ExportFormat.portrait);
    expect(source.sizes, [(4380, 6185)]);
    expect((result.image.width, result.image.height), (4380, 5475));
    expect(
      result.image.width * result.image.height,
      lessThanOrEqualTo(24000000),
    );
    expect(export.events, ['crop', 'render', 'compose', 'encode']);
    released(source, result);
  });

  test(
    'decoder OOM falls back through both levels without recapturing',
    () async {
      final source = Source(6000, 4000)..failures = 2;
      final result = await process(source);
      expect(source.sizes, [(6000, 4000), (4096, 2730), (2048, 1365)]);
      expect(result.metadata['quality'], 'standard');
      released(source, result);
    },
  );

  test(
    '700 MB guard skips a level before allocating a decoder surface',
    () async {
      final source = Source(16000, 4000);
      final result = await process(source, format: ExportFormat.square);
      // Maximum and High both need the full 64 MP input for this narrow crop;
      // Standard decodes 8192x2048 (201 MB) and fits.
      expect(source.sizes, [(8192, 2048)]);
      expect(result.metadata['quality'], 'standard');
      expect(
        log.recentLines.where((line) => line.contains('fallback')),
        hasLength(2),
      );
      released(source, result);
    },
  );

  test('terminal Standard failure propagates and leaks no surfaces', () async {
    final source = Source(6000, 4000)..failures = 3;
    await expectLater(process(source), throwsA(isA<OutOfMemoryError>()));
    expect(source.decoded, isEmpty);
    expect(export.surfaces, isEmpty);
  });

  test('cancelled requests allocate nothing', () async {
    final source = Source(6000, 4000);
    await expectLater(
      process(source, cancelled: () => true),
      throwsA(isA<ExportCancelled>()),
    );
    expect(source.sizes, isEmpty);
  });
  test('render target probe detects a clamped GPU dimension', () async {
    final attempts = <int>[];
    final limit = await PhotoExporter.probeTextureLimit(
      6000,
      supportsDimension: (side) async {
        attempts.add(side);
        return side <= 4096;
      },
    );
    expect(limit, 4096);
    expect(attempts.first, 6000);
    expect(attempts.length, lessThan(16));
  });

  test('GPU limit applies before decoding', () async {
    final source = Source(6000, 4000);
    final result =
        await PhotoExporter(
          export: export,
          log: log,
          textureProbe: (requested) async {
            expect(requested, 6000);
            return 4096;
          },
        ).process(
          source: source,
          quality: ExportQuality.maximum,
          format: ExportFormat.original,
          watermark: true,
          render: (image, maxSide) async =>
              export.surface(image.width, image.height),
        );
    expect(source.sizes, [(4096, 2730)]);
    expect(result.metadata['textureLimit'], 4096);
    released(source, result);
  });

  for (final layout in [ExportLayout.poster, ExportLayout.soundStrip]) {
    for (final limit in [4096, 2048]) {
      test('$layout fits a $limit GPU before any photo allocation', () async {
        final source = Source(3072, 4096);
        final unbounded = ExportLayoutPlan.build(
          layout: layout,
          photoWidth: 3072,
          photoHeight: 4096,
        );
        expect(unbounded.height, greaterThan(4096));
        final result =
            await PhotoExporter(
              export: export,
              log: log,
              textureProbe: (requested) async {
                expect(requested, unbounded.height);
                expect(source.sizes, isEmpty);
                return limit;
              },
            ).process(
              source: source,
              quality: ExportQuality.maximum,
              format: ExportFormat.original,
              layout: layout,
              watermark: false,
              values: const ExportLayoutValues(styleName: 'Prism', noiseDb: 28),
              render: (image, _) async =>
                  export.surface(image.width, image.height),
            );
        expect(source.sizes, hasLength(1));
        for (final image in [...source.decoded, ...export.surfaces]) {
          expect(image.width, lessThanOrEqualTo(limit));
          expect(image.height, lessThanOrEqualTo(limit));
        }
        expect(result.image.height, greaterThan(source.decoded.single.height));
        expect(result.metadata['layout'], layout.name);
        expect(log.recentLines.join('\n'), contains('export layout fallback'));
        released(source, result);
      });
    }
  }

  test(
    'an ID-only strip enters the texture probe and allocation limit',
    () async {
      final source = Source(3072, 4096);
      const values = ExportLayoutValues(styleName: '', photoId: 'A3F9-17C2');
      final unbounded = ExportLayoutPlan.build(
        layout: ExportLayout.soundStrip,
        photoWidth: source.width,
        photoHeight: source.height,
        readings: false,
        watermark: false,
        photoId: values.photoId,
      );
      final result =
          await PhotoExporter(
            export: export,
            log: log,
            textureProbe: (requested) async {
              expect(requested, unbounded.height);
              expect(requested, greaterThan(4096));
              expect(source.sizes, isEmpty);
              return 4096;
            },
          ).process(
            source: source,
            quality: ExportQuality.maximum,
            format: ExportFormat.original,
            layout: ExportLayout.soundStrip,
            watermark: false,
            values: values,
            render: (image, _) async =>
                export.surface(image.width, image.height),
          );
      expect(source.sizes, hasLength(1));
      for (final image in [...source.decoded, ...export.surfaces]) {
        expect(image.width, lessThanOrEqualTo(4096));
        expect(image.height, lessThanOrEqualTo(4096));
      }
      expect(result.image.height, greaterThan(source.decoded.single.height));
      released(source, result);
    },
  );

  test('layout surfaces enter the memory guard before decoding', () async {
    final source = Source(6000, 4000);
    final result =
        await PhotoExporter(
          export: export,
          log: log,
          textureProbe: (_) async => 16384,
        ).process(
          source: source,
          quality: ExportQuality.maximum,
          format: ExportFormat.original,
          layout: ExportLayout.poster,
          watermark: false,
          render: (image, _) async => export.surface(image.width, image.height),
        );
    expect(source.sizes, [(4096, 2730)]);
    expect(result.metadata['quality'], 'high');
    expect(
      result.metadata['estimatedBytes'],
      4096 * 2730 * 12 + result.image.width * result.image.height * 12,
    );
    expect(log.recentLines.join('\n'), contains('stage=memory guard'));
    released(source, result);
  });

  test(
    'pipeline diagnostics report the actual PNG after JPEG failure',
    () async {
      const channel = MethodChannel(ImageEncoder.channelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map<Object?, Object?>;
            File(args['outputPath']! as String)
                .writeAsStringSync('partial jpeg');
            throw PlatformException(code: 'encode_failed');
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final source = Source(40, 20);
      final result =
          await PhotoExporter(
            export: export,
            log: log,
            textureProbe: (_) async => 4096,
          ).process(
            source: source,
            quality: ExportQuality.standard,
            format: ExportFormat.original,
            watermark: false,
            fileType: ExportFileType.jpeg,
            render: (image, _) async =>
                export.surface(image.width, image.height),
          );
      expect(result.file.path, endsWith('.png'));
      expect(result.file.existsSync(), isTrue);
      expect(result.metadata['requestedFileType'], 'jpeg');
      expect(result.metadata['fileType'], 'png');
      expect(
        log.recentLines.last,
        contains('PNG layout=full requestedFileType=jpeg'),
      );
      expect(
        directory.listSync().where((file) => file.path.endsWith('.jpg')),
        isEmpty,
      );
      released(source, result);
    },
  );

  test('render target probe propagates unrelated errors', () async {
    final failure = StateError('Probe bug');
    await expectLater(
      PhotoExporter.probeTextureLimit(
        6000,
        supportsDimension: (_) async => throw failure,
      ),
      throwsA(same(failure)),
    );
  });

  test(
    'cancellation after decode frees the input without a lower-tier retry',
    () async {
      final source = Source(6000, 4000);
      await expectLater(
        process(source, cancelled: () => source.decoded.isNotEmpty),
        throwsA(isA<ExportCancelled>()),
      );
      expect(source.decoded.single.disposals, 1);
      expect(export.surfaces, isEmpty);
      expect(log.recentLines, isEmpty);
    },
  );

  test('guard includes the compressed original in its estimate', () async {
    final source = Source(6000, 4000)..compressedBytes = 500000000;
    final result = await process(source);
    expect(source.sizes, [(4096, 2730)]);
    expect(result.metadata['quality'], 'high');
    released(source, result);
  });

  test(
    'guard and metadata include the retained full-resolution image',
    () async {
      final source = Source(6000, 4000)..compressedBytes = 320000000;
      // Without the previous 24 MP result, Maximum would fit (608 MB).
      final result = await process(source, retainedImageBytes: 96000000);
      expect(source.sizes, [(4096, 2730)]);
      expect(result.metadata['quality'], 'high');
      expect(
        result.metadata['estimatedBytes'],
        4096 * 2730 * 4 * 3 + 320000000 + 96000000,
      );
      expect(log.recentLines.join('\n'), contains('704000000 bytes exceeds'));
      released(source, result);
    },
  );
}
