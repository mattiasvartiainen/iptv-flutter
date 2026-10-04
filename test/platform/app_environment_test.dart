import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/platform/app_environment.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';

void main() {
  testWidgets('AppEnvironment exposes the injected capabilities', (
    tester,
  ) async {
    const capabilities = PlatformCapabilities(
      primaryInput: PrimaryInput.remote,
      hasHardwareBack: true,
      supportsHover: false,
    );
    await tester.pumpWidget(
      const AppEnvironment(
        capabilities: capabilities,
        child: _EnvironmentReader(),
      ),
    );

    final observed = AppEnvironment.of(
      tester.element(find.byType(_EnvironmentReader)),
    );

    expect(observed, capabilities);
    expect(observed.isRemoteFirst, isTrue);
  });
}

class _EnvironmentReader extends StatelessWidget {
  const _EnvironmentReader();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
