import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/features/settings/widgets/telemetry_section.dart';
import 'package:iptv_flutter/platform/telemetry_settings_store.dart';
import 'package:iptv_flutter/services/telemetry/otlp_app_telemetry.dart';
import 'package:iptv_flutter/services/telemetry/telemetry_config.dart';
import 'package:iptv_flutter/state/telemetry_controller.dart';

class _MemoryStore implements TelemetrySettingsStore {
  final readResult = Completer<TelemetryConfig?>();
  final writes = <TelemetryConfig>[];
  Completer<void>? writeGate;
  bool failWrite = false;

  @override
  Future<TelemetryConfig?> read() => readResult.future;

  @override
  Future<void> write(TelemetryConfig config) async {
    writes.add(config);
    await writeGate?.future;
    if (failWrite) throw StateError('sensitive storage error');
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

Future<void> _mount(
  WidgetTester tester,
  TelemetryController controller, {
  double width = 1200,
  double scale = 1,
  NavigationMode navigationMode = NavigationMode.traditional,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          navigationMode: navigationMode,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: TelemetrySection(controller: controller),
        ),
      ),
    ),
  );
}

bool _hasFocus(Finder finder) {
  final target = finder.evaluate().single;
  var found = false;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
    if (element == target) found = true;
    return !found;
  });
  return found;
}

Future<void> _keyPress(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

List<Finder> _controls() => [
  find.byWidgetPredicate(
    (widget) =>
        widget is SwitchListTile &&
        (widget.title as Text).data == 'Send telemetry',
  ),
  _field('OTLP HTTP endpoint'),
  _field('Service name'),
  _field('Device alias'),
  _field('OTLP API key (optional)'),
  find.byWidgetPredicate(
    (widget) =>
        widget is SwitchListTile &&
        (widget.title as Text).data == 'Include diagnostic stacks',
  ),
  find.byWidgetPredicate((widget) => widget is FilledButton),
  find.byWidgetPredicate((widget) => widget is OutlinedButton),
];

void main() {
  late _MemoryStore store;
  late OtlpAppTelemetry telemetry;
  late TelemetryController controller;

  setUp(() {
    store = _MemoryStore();
    telemetry = OtlpAppTelemetry();
    controller = TelemetryController(
      telemetry: telemetry,
      defaults: const TelemetryConfig(),
      store: store,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets('loads persisted config after mount', (tester) async {
    late Future<void> initialization;
    await tester.runAsync(() async {
      initialization = controller.initialize();
    });
    await _mount(tester, controller);
    expect(_text(tester, 'OTLP HTTP endpoint'), 'http://localhost:4318');
    await tester.runAsync(() async {
      store.readResult.complete(
        const TelemetryConfig(
          endpoint: 'https://collector.example',
          serviceName: 'saved-service',
          deviceAlias: 'saved-device',
          apiKey: 'saved-secret',
          verbose: true,
        ),
      );
      await initialization;
    });
    await tester.pump();
    expect(_text(tester, 'OTLP HTTP endpoint'), 'https://collector.example');
    expect(_text(tester, 'Service name'), 'saved-service');
    expect(_text(tester, 'Device alias'), 'saved-device');
    expect(_text(tester, 'OTLP API key (optional)'), 'saved-secret');
    expect(
      tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).last.value,
      isTrue,
    );
    expect(telemetry.config.enabled, isFalse);
  });

  testWidgets('remote enables an unsaved endpoint for this session', (
    tester,
  ) async {
    await _mount(
      tester,
      controller,
      navigationMode: NavigationMode.directional,
    );
    await tester.enterText(
      _field('OTLP HTTP endpoint'),
      'http://127.0.0.1:4318',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(_hasFocus(_controls().first), isTrue);
    final activated = Completer<void>();
    controller.addListener(() {
      if (!controller.busy &&
          controller.config.enabled &&
          !activated.isCompleted) {
        activated.complete();
      }
    });
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 450));
      await activated.future;
    });
    await tester.pump();
    expect(telemetry.enabled, isTrue);
    expect(controller.config.endpoint, 'http://127.0.0.1:4318');
    expect(store.writes, isEmpty);
    expect(
      find.text('Telemetry enabled for this session. Apply to save.'),
      findsOneWidget,
    );
    await tester.runAsync(telemetry.close);
  });

  testWidgets('Apply reports persistence failure without exposing details', (
    tester,
  ) async {
    store.failWrite = true;
    await _mount(tester, controller);
    await tester.ensureVisible(find.text('Apply'));
    await tester.runAsync(() async => tester.tap(find.text('Apply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('settings could not be saved'), findsOneWidget);
    expect(find.textContaining('sensitive storage error'), findsNothing);
  });

  testWidgets('late config preserves active editing even before text changes', (
    tester,
  ) async {
    late Future<void> initialization;
    await tester.runAsync(() async {
      initialization = controller.initialize();
    });
    await _mount(tester, controller);
    await tester.tap(_field('OTLP HTTP endpoint'));
    await tester.pump();
    final editing = tester
        .widget<TextField>(_field('OTLP HTTP endpoint'))
        .controller!;
    final selection = editing.selection;
    await tester.runAsync(() async {
      store.readResult.complete(
        const TelemetryConfig(endpoint: 'https://late.example'),
      );
      await initialization;
    });
    await tester.pump();
    expect(editing.text, 'http://localhost:4318');
    expect(editing.selection, selection);
    expect(_hasFocus(_field('OTLP HTTP endpoint')), isTrue);
  });

  testWidgets('late config preserves unfocused unsaved draft and toggles', (
    tester,
  ) async {
    late Future<void> initialization;
    await tester.runAsync(() async {
      initialization = controller.initialize();
    });
    await _mount(tester, controller);
    await tester.enterText(_field('Service name'), 'unsaved-service');
    await tester.tap(find.text('Include diagnostic stacks'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.runAsync(() async {
      store.readResult.complete(
        const TelemetryConfig(serviceName: 'stored-service'),
      );
      await initialization;
    });
    await tester.pump();
    expect(_text(tester, 'Service name'), 'unsaved-service');
    expect(
      tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).last.value,
      isTrue,
    );
  });

  testWidgets('busy and status notifications preserve every draft field', (
    tester,
  ) async {
    await _mount(tester, controller);
    final drafts = {
      'OTLP HTTP endpoint': 'https://draft.example',
      'Service name': 'draft-service',
      'Device alias': 'draft-device',
      'OTLP API key (optional)': 'draft-secret',
    };
    for (final entry in drafts.entries) {
      await tester.ensureVisible(_field(entry.key));
      await tester.enterText(_field(entry.key), entry.value);
    }
    store.writeGate = Completer<void>();
    late Future<bool> saving;
    await tester.runAsync(() async {
      saving = controller.save(const TelemetryConfig());
    });
    await tester.pump();
    expect(controller.busy, isTrue);
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((widget) => widget is FilledButton),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .every((tile) => tile.onChanged == null),
      isTrue,
    );
    for (final entry in drafts.entries) {
      expect(_text(tester, entry.key), entry.value);
    }
    await tester.runAsync(() async {
      store.writeGate!.complete();
      await saving;
    });
    await tester.pump();
    expect(find.text('Telemetry disabled.'), findsOneWidget);
    for (final entry in drafts.entries) {
      expect(_text(tester, entry.key), entry.value);
    }
  });

  testWidgets('validates endpoint and names; optional key is obscured', (
    tester,
  ) async {
    await _mount(tester, controller);
    final keyField = tester.widget<TextField>(
      _field('OTLP API key (optional)'),
    );
    expect(keyField.obscureText, isTrue);
    expect(keyField.autocorrect, isFalse);
    expect(keyField.enableSuggestions, isFalse);
    expect(keyField.controller!.text, isEmpty);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Send test telemetry'),
          )
          .onPressed,
      isNull,
    );
    for (final endpoint in [
      'invalid',
      'http://localhost:18888',
      'https://collector.example/v1/logs',
    ]) {
      await tester.enterText(_field('OTLP HTTP endpoint'), endpoint);
      await tester.ensureVisible(find.text('Apply'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter an OTLP HTTP base URL, not the dashboard UI URL.'),
        findsOneWidget,
      );
      expect(store.writes, isEmpty);
    }
    await tester.enterText(
      _field('OTLP HTTP endpoint'),
      'https://collector.example',
    );
    await tester.enterText(_field('Service name'), '');
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
      find.text('Service and device names must contain 1 to 80 characters.'),
      findsOneWidget,
    );
    expect(store.writes, isEmpty);
    await tester.enterText(_field('Service name'), 'living-room');
    await tester.ensureVisible(find.text('Apply'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Apply'));
    });
    await tester.pumpAndSettle();
    expect(store.writes.single.apiKey, isEmpty);
    expect(store.writes.single.serviceName, 'living-room');
    expect(find.text('Telemetry disabled.'), findsOneWidget);
    expect(telemetry.deliveries, isEmpty);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'no overflow at width $width with 2x text and validation/status',
      (tester) async {
        await _mount(tester, controller, width: width, scale: 2);
        await tester.enterText(_field('OTLP HTTP endpoint'), 'invalid');
        await tester.ensureVisible(find.text('Apply'));
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await controller.save(const TelemetryConfig(endpoint: 'invalid'));
        });
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('telemetry-status')),
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final reverse in [false, true]) {
      testWidgets(
        '${reverse ? 'ShiftTab' : 'Tab'} reaches every control at width $width without SDK setup',
        (tester) async {
          telemetry.config = const TelemetryConfig(enabled: true);
          await _mount(tester, controller, width: width);
          final targets = _controls();
          final visited = <int>{};
          if (reverse) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          }
          try {
            for (
              var step = 0;
              step < 20 && visited.length < targets.length;
              step++
            ) {
              await _keyPress(tester, LogicalKeyboardKey.tab);
              for (var index = 0; index < targets.length; index++) {
                if (_hasFocus(targets[index])) visited.add(index);
              }
            }
          } finally {
            if (reverse) {
              await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
            }
          }
          expect(
            visited,
            containsAll(List.generate(targets.length, (index) => index)),
          );
          expect(tester.takeException(), isNull);
          expect(telemetry.deliveries, isEmpty);
        },
      );
    }

    testWidgets(
      'Dpad reaches every control at width $width without SDK setup',
      (tester) async {
        telemetry.config = const TelemetryConfig(enabled: true);
        await _mount(
          tester,
          controller,
          width: width,
          navigationMode: NavigationMode.directional,
        );
        final targets = _controls();
        await _keyPress(tester, LogicalKeyboardKey.tab);
        expect(_hasFocus(targets.first), isTrue);
        final visited = <int>{0};
        for (var step = 0; step < 14; step++) {
          await _keyPress(tester, LogicalKeyboardKey.arrowDown);
          for (var index = 0; index < targets.length; index++) {
            if (_hasFocus(targets[index])) visited.add(index);
          }
        }
        for (final key in [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
        ]) {
          await _keyPress(tester, key);
          for (var index = 0; index < targets.length; index++) {
            if (_hasFocus(targets[index])) visited.add(index);
          }
        }
        expect(
          visited,
          containsAll(List.generate(targets.length, (index) => index)),
        );
        for (var step = 0; step < 14 && !_hasFocus(targets.first); step++) {
          await _keyPress(tester, LogicalKeyboardKey.arrowUp);
        }
        expect(_hasFocus(targets.first), isTrue);
        expect(tester.takeException(), isNull);
        expect(telemetry.deliveries, isEmpty);
      },
    );

    testWidgets('keyboard activates toggles and Apply at width $width', (
      tester,
    ) async {
      telemetry.config = const TelemetryConfig(enabled: true);
      await _mount(tester, controller, width: width);
      final controls = _controls();
      await _keyPress(tester, LogicalKeyboardKey.tab);
      await _keyPress(tester, LogicalKeyboardKey.enter);
      expect(tester.widget<SwitchListTile>(controls.first).value, isFalse);
      for (var step = 0; step < 12 && !_hasFocus(controls[5]); step++) {
        await _keyPress(tester, LogicalKeyboardKey.tab);
      }
      expect(_hasFocus(controls[5]), isTrue);
      await _keyPress(tester, LogicalKeyboardKey.enter);
      expect(tester.widget<SwitchListTile>(controls[5]).value, isTrue);
      await _keyPress(tester, LogicalKeyboardKey.tab);
      expect(_hasFocus(controls[6]), isTrue);
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      });
      await tester.pumpAndSettle();
      expect(store.writes.single.enabled, isFalse);
      expect(store.writes.single.verbose, isTrue);
      expect(controller.status, 'Telemetry disabled.');
      expect(telemetry.deliveries, isEmpty);
    });
  }

  testWidgets('traditional keyboard arrows still edit text', (tester) async {
    await _mount(tester, controller);
    await tester.enterText(_field('Service name'), 'living-room');
    final editing = tester
        .widget<TextField>(_field('Service name'))
        .controller!;
    editing.selection = TextSelection.collapsed(offset: editing.text.length);
    await _keyPress(tester, LogicalKeyboardKey.arrowLeft);
    expect(editing.selection.baseOffset, editing.text.length - 1);
    await _keyPress(tester, LogicalKeyboardKey.arrowUp);
    expect(_hasFocus(_field('Service name')), isTrue);
  });

  testWidgets('Apply preserves loaded HTTP JSON protocol', (tester) async {
    await tester.runAsync(() async {
      await telemetry.configure(const TelemetryConfig(protocol: 'http/json'));
    });
    await _mount(tester, controller);
    await tester.ensureVisible(find.text('Apply'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Apply'));
    });
    await tester.pumpAndSettle();
    expect(store.writes.single.protocol, 'http/json');
    expect(telemetry.deliveries, isEmpty);
  });

  testWidgets(
    'successful Apply resets draft baseline for later config changes',
    (tester) async {
      await _mount(tester, controller);
      await tester.enterText(_field('Service name'), 'saved-draft');
      await tester.ensureVisible(find.text('Apply'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Apply'));
      });
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.runAsync(() async {
        await controller.save(
          const TelemetryConfig(
            endpoint: 'https://updated.example',
            serviceName: 'updated-service',
          ),
        );
      });
      await tester.pump();
      expect(_text(tester, 'OTLP HTTP endpoint'), 'https://updated.example');
      expect(_text(tester, 'Service name'), 'updated-service');
    },
  );

  testWidgets(
    'value-equivalent config notification leaves field selection intact',
    (tester) async {
      await _mount(tester, controller);
      final editing = tester
          .widget<TextField>(_field('Service name'))
          .controller!;
      editing.selection = const TextSelection.collapsed(offset: 2);
      final value = editing.value;
      final before = controller.config;
      await tester.runAsync(() async {
        await controller.save(TelemetryConfig());
      });
      await tester.pump();
      expect(identical(controller.config, before), isFalse);
      expect(editing.value, value);
    },
  );

  testWidgets(
    'whitespace-only draft edits are not overwritten by config changes',
    (tester) async {
      await _mount(tester, controller);
      await tester.enterText(_field('Service name'), 'iptv-app ');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.runAsync(() async {
        await controller.save(
          const TelemetryConfig(serviceName: 'updated-service'),
        );
      });
      await tester.pump();
      expect(_text(tester, 'Service name'), 'iptv-app ');
    },
  );
}
