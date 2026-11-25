import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/playback/playback_video_surface.dart';

void main() {
  testWidgets(
    'native child stays mounted while aspect ratio reacts to values',
    (tester) async {
      final values = ValueNotifier<double>(16 / 9);
      addTearDown(values.dispose);
      var nativeBuilds = 0;
      final view = PlaybackVideoSurface<double>(
        values: values,
        aspectRatio: (value) => value,
        child: _NativeChild(onBuild: () => nativeBuilds++),
      );
      await tester.pumpWidget(MaterialApp(home: Center(child: view)));
      final original = tester.element(find.byType(_NativeChild));
      expect(nativeBuilds, 1);
      for (final ratio in [4 / 3, 1.0, 16 / 9]) {
        values.value = ratio;
        await tester.pump();
        expect(
          tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
          ratio,
        );
        expect(tester.element(find.byType(_NativeChild)), same(original));
        expect(nativeBuilds, 1);
      }
      await tester.pumpWidget(const SizedBox());
      final buildsAfterUnmount = nativeBuilds;
      values.value = 2;
      await tester.pump();
      expect(nativeBuilds, buildsAfterUnmount);
      expect(tester.takeException(), isNull);
    },
  );

  for (final ratio in [0.0, -1.0, double.nan, double.infinity]) {
    testWidgets('invalid aspect ratio $ratio uses finite 16:9 fallback', (
      tester,
    ) async {
      final values = ValueNotifier<double>(ratio);
      addTearDown(values.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackVideoSurface<double>(
            values: values,
            aspectRatio: (value) => value,
            child: const SizedBox(),
          ),
        ),
      );
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        16 / 9,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

class _NativeChild extends StatelessWidget {
  const _NativeChild({required this.onBuild});
  final VoidCallback onBuild;
  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox.expand();
  }
}
