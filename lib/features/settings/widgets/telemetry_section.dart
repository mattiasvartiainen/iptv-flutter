import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/telemetry/telemetry_config.dart';
import '../../../state/telemetry_controller.dart';

class TelemetrySection extends StatefulWidget {
  const TelemetrySection({super.key, required this.controller});

  final TelemetryController controller;

  @override
  State<TelemetrySection> createState() => _TelemetrySectionState();
}

class _TelemetrySectionState extends State<TelemetrySection> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _endpoint;
  late final TextEditingController _service;
  late final TextEditingController _device;
  late final TextEditingController _key;
  late bool _enabled;
  late bool _verbose;
  late TelemetryConfig _observedConfig;
  late TelemetryConfig _draftBase;
  final _fieldFocus = List.generate(4, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    final config = widget.controller.config;
    _endpoint = TextEditingController(text: config.endpoint);
    _service = TextEditingController(text: config.serviceName);
    _device = TextEditingController(text: config.deviceAlias);
    _key = TextEditingController(text: config.apiKey);
    _enabled = config.enabled;
    _verbose = config.verbose;
    _observedConfig = config;
    _draftBase = config;
    widget.controller.addListener(_syncConfig);
  }

  bool _sameConfig(TelemetryConfig first, TelemetryConfig second) =>
      first.enabled == second.enabled &&
      first.endpoint == second.endpoint &&
      first.serviceName == second.serviceName &&
      first.deviceAlias == second.deviceAlias &&
      first.apiKey == second.apiKey &&
      first.verbose == second.verbose &&
      first.protocol == second.protocol;

  void _syncConfig() {
    final next = widget.controller.config;
    if (_sameConfig(next, _observedConfig)) return;
    _observedConfig = next;
    if (_sameConfig(next, _config())) {
      _draftBase = next;
      return;
    }
    if (_endpoint.text != _draftBase.endpoint ||
        _service.text != _draftBase.serviceName ||
        _device.text != _draftBase.deviceAlias ||
        _key.text != _draftBase.apiKey ||
        _enabled != _draftBase.enabled ||
        _verbose != _draftBase.verbose ||
        _fieldFocus.any((node) => node.hasFocus)) {
      return;
    }
    _draftBase = next;
    _endpoint.text = next.endpoint;
    _service.text = next.serviceName;
    _device.text = next.deviceAlias;
    _key.text = next.apiKey;
    setState(() {
      _enabled = next.enabled;
      _verbose = next.verbose;
    });
  }

  @override
  void didUpdateWidget(covariant TelemetrySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncConfig);
      widget.controller.addListener(_syncConfig);
      _syncConfig();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncConfig);
    for (final node in _fieldFocus) {
      node.dispose();
    }
    _endpoint.dispose();
    _service.dispose();
    _device.dispose();
    _key.dispose();
    super.dispose();
  }

  TelemetryConfig _config() => TelemetryConfig(
    enabled: _enabled,
    endpoint: _endpoint.text.trim(),
    serviceName: _service.text.trim(),
    deviceAlias: _device.text.trim(),
    verbose: _verbose,
    apiKey: _key.text.trim(),
    protocol: _draftBase.protocol,
  );

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await widget.controller.save(_config());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (MediaQuery.navigationModeOf(context) !=
                NavigationMode.directional ||
            event is KeyUpEvent) {
          return KeyEventResult.ignored;
        }
        final direction = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowUp => TraversalDirection.up,
          LogicalKeyboardKey.arrowDown => TraversalDirection.down,
          _ => null,
        };
        if (direction == null) return KeyEventResult.ignored;
        FocusManager.instance.primaryFocus?.focusInDirection(direction);
        return KeyEventResult.handled;
      },
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Diagnostics', style: Theme.of(context).textTheme.titleLarge),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Send telemetry'),
              value: _enabled,
              onChanged: widget.controller.busy
                  ? null
                  : (value) => setState(() => _enabled = value),
            ),
            TextFormField(
              controller: _endpoint,
              focusNode: _fieldFocus[0],
              decoration: const InputDecoration(
                labelText: 'OTLP HTTP endpoint',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (_) {
                try {
                  _config().validate();
                  return null;
                } on FormatException catch (error) {
                  return error.message;
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _service,
              focusNode: _fieldFocus[1],
              decoration: const InputDecoration(labelText: 'Service name'),
              maxLength: 80,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _device,
              focusNode: _fieldFocus[2],
              decoration: const InputDecoration(labelText: 'Device alias'),
              maxLength: 80,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _key,
              focusNode: _fieldFocus[3],
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'OTLP API key (optional)',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include diagnostic stacks'),
              value: _verbose,
              onChanged: widget.controller.busy
                  ? null
                  : (value) => setState(() => _verbose = value),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: widget.controller.busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Apply'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      widget.controller.busy ||
                          !widget.controller.config.enabled
                      ? null
                      : widget.controller.sendTest,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Send test telemetry'),
                ),
              ],
            ),
            if (widget.controller.status case final status?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(status, key: const ValueKey('telemetry-status')),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}
