class TelemetryConfig {
  const TelemetryConfig({
    this.enabled = false,
    this.endpoint = 'http://localhost:4318',
    this.serviceName = 'iptv-app',
    this.deviceAlias = 'development',
    this.verbose = false,
    this.apiKey = '',
    this.protocol = 'http/protobuf',
  });

  final bool enabled;
  final String endpoint;
  final String serviceName;
  final String deviceAlias;
  final bool verbose;
  final String apiKey;
  final String protocol;

  void validate() {
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        endpoint.contains(RegExp(r'\s')) ||
        uri.port == 18888) {
      throw const FormatException(
        'Enter an OTLP HTTP base URL, not the dashboard UI URL.',
      );
    }
    if (serviceName.trim().isEmpty ||
        deviceAlias.trim().isEmpty ||
        serviceName.length > 80 ||
        deviceAlias.length > 80) {
      throw const FormatException(
        'Service and device names must contain 1 to 80 characters.',
      );
    }
    if (!const ['http/protobuf', 'http/json'].contains(protocol)) {
      throw const FormatException('Unsupported OTLP HTTP protocol.');
    }
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'endpoint': endpoint,
    'serviceName': serviceName,
    'deviceAlias': deviceAlias,
    'verbose': verbose,
    'protocol': protocol,
  };

  factory TelemetryConfig.fromJson(
    Map<String, dynamic> json, {
    String apiKey = '',
  }) => TelemetryConfig(
    enabled: json['enabled'] as bool? ?? false,
    endpoint: json['endpoint'] as String? ?? 'http://localhost:4318',
    serviceName: json['serviceName'] as String? ?? 'iptv-app',
    deviceAlias: json['deviceAlias'] as String? ?? 'development',
    verbose: json['verbose'] as bool? ?? false,
    protocol: json['protocol'] as String? ?? 'http/protobuf',
    apiKey: apiKey,
  );
}
