class AutomaticContentPolicy {
  const AutomaticContentPolicy._();

  static const groupMarkers = ['adult', 'xxx', '18+', 'porn'];
  static const titleMarkers = [
    '[xxx]',
    '(xxx)',
    '[adult]',
    '(adult)',
    '[18+]',
    '(18+)',
  ];

  static bool excludesGroup(String title) => _matches(title, groupMarkers);
  static bool excludesTitle(String title) => _matches(title, titleMarkers);

  static bool _matches(String value, List<String> markers) {
    final normalized = value.toLowerCase();
    return markers.any(normalized.contains);
  }
}
