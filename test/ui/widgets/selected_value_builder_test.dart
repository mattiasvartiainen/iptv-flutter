import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/ui/widgets/selected_value_builder.dart';

void main() {
  testWidgets('100 unrelated ticks cause zero additional selected builds', (
    tester,
  ) async {
    final source = ValueNotifier((position: 0, title: 'Movie'));
    addTearDown(source.dispose);
    var builds = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SelectedValueBuilder<({int position, String title}), String>(
          valueListenable: source,
          select: (value) => value.title,
          builder: (_, title) {
            builds++;
            return Text(title);
          },
        ),
      ),
    );
    expect(builds, 1);
    for (var i = 1; i <= 100; i++) {
      source.value = (position: i, title: 'Movie');
      await tester.pump();
    }
    expect(builds, 1);
    source.value = (position: 101, title: 'Next');
    await tester.pump();
    expect(builds, 2);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('disabled slices detach and catch up on reveal', (tester) async {
    final source = _CountingNotifier(0);
    addTearDown(source.dispose);
    var builds = 0;
    Widget view(bool enabled) => Directionality(
      textDirection: TextDirection.ltr,
      child: SelectedValueBuilder<int, int>(
        valueListenable: source,
        enabled: enabled,
        select: (value) => value,
        builder: (_, value) {
          builds++;
          return Text('$value');
        },
      ),
    );
    await tester.pumpWidget(view(true));
    expect(source.listeners, 1);
    await tester.pumpWidget(view(false));
    expect(source.listeners, 0);
    final hiddenBuilds = builds;
    for (var i = 1; i <= 100; i++) {
      source.value = i;
      await tester.pump();
    }
    expect(builds, hiddenBuilds);
    await tester.pumpWidget(view(true));
    expect(find.text('100'), findsOneWidget);
    expect(source.listeners, 1);
    await tester.pumpWidget(const SizedBox());
    expect(source.listeners, 0);
  });

  testWidgets(
    'source and selector replacement refresh without stale listeners',
    (tester) async {
      final first = _CountingNotifier(1);
      final second = _CountingNotifier(2);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget view(ValueNotifier<int> source, int multiplier) => Directionality(
        textDirection: TextDirection.ltr,
        child: SelectedValueBuilder<int, int>(
          valueListenable: source,
          select: (value) => value * multiplier,
          builder: (_, value) => Text('$value'),
        ),
      );
      await tester.pumpWidget(view(first, 1));
      await tester.pumpWidget(view(second, 10));
      expect(first.listeners, 0);
      expect(second.listeners, 1);
      expect(find.text('20'), findsOneWidget);
      first.value = 100;
      await tester.pump();
      expect(find.text('20'), findsOneWidget);
      second.value = 3;
      await tester.pump();
      expect(find.text('30'), findsOneWidget);
      await tester.pumpWidget(view(second, 100));
      expect(find.text('300'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(second.listeners, 0);
    },
  );
}

class _CountingNotifier extends ValueNotifier<int> {
  _CountingNotifier(super.value);
  int listeners = 0;
  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }
}
