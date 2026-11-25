import 'package:flutter/material.dart';

import '../../../ui/formatting.dart';

class PlayerSeekBar extends StatelessWidget {
  const PlayerSeekBar({
    super.key,
    required this.focusNode,
    required this.position,
    required this.duration,
    required this.preview,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final FocusNode focusNode;
  final Duration position;
  final Duration duration;
  final double? preview;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Slider(
        key: const ValueKey('player-seek'),
        focusNode: focusNode,
        semanticFormatterCallback: (value) =>
            formatDuration(Duration(milliseconds: value.round())),
        value: (preview ?? position.inMilliseconds.toDouble()).clamp(
          0,
          duration.inMilliseconds.toDouble(),
        ),
        max: duration.inMilliseconds.toDouble(),
        onChangeStart: onChangeStart,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        children: [
          Text(
            formatDuration(
              preview == null
                  ? position
                  : Duration(milliseconds: preview!.round()),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          Text(
            formatDuration(duration),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    ],
  );
}
