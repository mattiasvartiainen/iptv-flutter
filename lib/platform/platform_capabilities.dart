import 'package:flutter/foundation.dart';

enum PrimaryInput { remote, pointer, touch }

@immutable
class PlatformCapabilities {
  const PlatformCapabilities({
    required this.primaryInput,
    required this.hasHardwareBack,
    required this.supportsHover,
  });

  final PrimaryInput primaryInput;
  final bool hasHardwareBack;
  final bool supportsHover;

  bool get isRemoteFirst => primaryInput == PrimaryInput.remote;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlatformCapabilities &&
          primaryInput == other.primaryInput &&
          hasHardwareBack == other.hasHardwareBack &&
          supportsHover == other.supportsHover;

  @override
  int get hashCode => Object.hash(primaryInput, hasHardwareBack, supportsHover);
}
