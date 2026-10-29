import 'package:flutter/material.dart';

import '../../ambient/ambient_controller.dart';
import '../../ambient/screenshot_values.dart';
import '../../theme/app_theme.dart';

/// English-only tooling, mounted exclusively by private screenshot builds.
class ScreenshotSection extends StatelessWidget {
  const ScreenshotSection({super.key, required this.ambient});

  final AmbientController ambient;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ambient,
    builder: (context, _) {
      final values = ambient.screenshotValues;
      Widget slider(
        String label,
        double value,
        ValueChanged<double> update, {
        double min = 0,
        double max = 1,
        int decimals = 2,
      }) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label: ${value.toStringAsFixed(decimals)}'),
            Slider(
              key: ValueKey('screenshot-$label'),
              value: value,
              min: min,
              max: max,
              label: value.toStringAsFixed(decimals),
              semanticFormatterCallback: (value) =>
                  '$label: ${value.toStringAsFixed(decimals)}',
              onChanged: update,
            ),
          ],
        ),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Screenshot mode',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text('Screenshot mode (not for stores)'),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Demo values'),
            value: ambient.demoValuesEnabled,
            onChanged: ambient.setDemoValues,
          ),
          Padding(
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            child: Wrap(
              spacing: AppTheme.spaceSm,
              children: [
                for (final preset in [
                  ScreenshotValues.calm,
                  ScreenshotValues.lively,
                  ScreenshotValues.intense,
                ])
                  ChoiceChip(
                    label: Text(preset.preset),
                    selected: values.preset == preset.preset,
                    onSelected: (_) => ambient.setScreenshotValues(preset),
                  ),
                ChoiceChip(
                  label: const Text('Custom'),
                  selected: values.preset == 'Custom',
                  onSelected: (_) =>
                      ambient.setScreenshotValues(values.copyWith()),
                ),
              ],
            ),
          ),
          slider(
            'Noise',
            values.noise,
            (v) => ambient.setScreenshotValues(values.copyWith(noise: v)),
          ),
          slider(
            'Light',
            values.light,
            (v) => ambient.setScreenshotValues(values.copyWith(light: v)),
          ),
          slider(
            'Motion',
            values.motion,
            (v) => ambient.setScreenshotValues(values.copyWith(motion: v)),
          ),
          slider(
            'Sound dB',
            values.db,
            (v) => ambient.setScreenshotValues(values.copyWith(db: v)),
            min: 30,
            max: 100,
            decimals: 0,
          ),
          slider(
            'Light lx',
            values.lux,
            (v) => ambient.setScreenshotValues(values.copyWith(lux: v)),
            max: 2000,
            decimals: 0,
          ),
          slider(
            'Motion m/s²',
            values.accel,
            (v) => ambient.setScreenshotValues(values.copyWith(accel: v)),
            max: 2,
          ),
          slider(
            'Bass',
            values.bass,
            (v) => ambient.setScreenshotValues(values.copyWith(bass: v)),
          ),
          slider(
            'Mid',
            values.mid,
            (v) => ambient.setScreenshotValues(values.copyWith(mid: v)),
          ),
          slider(
            'Treble',
            values.treble,
            (v) => ambient.setScreenshotValues(values.copyWith(treble: v)),
          ),
        ],
      );
    },
  );
}
