import '../../models/content_item.dart';
import 'id_identity.dart';

class M3uParser {
  const M3uParser();

  static final RegExp _attributePattern = RegExp(
    r'''([\w-]+)=(?:"([^"]*)"|([^\s,]+))''',
  );
  static final RegExp _contentTypeHintPattern = RegExp(
    r'\b(vod|movie|movies|film|series|episode)\b',
  );

  /// Attributes worth carrying on every [ContentItem]. A playlist can attach
  /// dozens of provider-specific attributes per entry; at half a million
  /// entries, retaining all of them costs more memory than the catalog rows
  /// themselves, and only these four are ever read again.
  static const List<String> _retainedAttributes = [
    'tvg-id',
    'tvg-name',
    'tvg-chno',
    'xui-id',
  ];

  List<ContentItem> parse(String text, {String? sourceUrl}) {
    final items = <ContentItem>[];
    String? metadataLine;

    // Scanned by index rather than split into a list of lines: a 500k-item
    // playlist would otherwise hold ~1M line strings alive at once, on top
    // of the source text and the parsed items.
    final length = text.length;
    var cursor = 0;
    while (cursor < length) {
      var breakAt = text.indexOf('\n', cursor);
      if (breakAt < 0) breakAt = length;
      var lineEnd = breakAt;
      if (lineEnd > cursor && text.codeUnitAt(lineEnd - 1) == 0x0d) lineEnd--;
      final line = text.substring(cursor, lineEnd).trim();
      cursor = breakAt + 1;

      if (line.isEmpty || line.startsWith('#EXTM3U')) continue;
      if (line.startsWith('#EXTINF')) {
        metadataLine = line;
        continue;
      }
      if (line.startsWith('#')) continue;
      if (metadataLine == null) continue;

      final attributes = _attributes(metadataLine);
      final comma = metadataLine.indexOf(',');
      final title = comma >= 0 && comma + 1 < metadataLine.length
          ? metadataLine.substring(comma + 1).trim()
          : '';
      final resolvedUrl = _resolveUrl(line, sourceUrl);
      final group =
          _first(attributes, const ['group-title', 'group']) ?? 'Uncategorized';
      final logo = _first(attributes, const ['tvg-logo', 'logo']);
      final itemTitle = title.isEmpty
          ? (attributes['tvg-name'] ?? resolvedUrl)
          : title;

      final identityNamespace = sourceUrl ?? '';
      items.add(
        ContentItem(
          id: strongStableId(
            'item',
            '$identityNamespace|$resolvedUrl|$itemTitle|${items.length}',
          ),
          title: itemTitle,
          type: _contentType(attributes, group, resolvedUrl),
          streamUrl: resolvedUrl,
          group: group.isEmpty ? 'Uncategorized' : group,
          logoUrl: logo?.isEmpty == true ? null : logo,
          metadata: _retain(attributes),
          sourceIndex: items.length,
        ),
      );
      metadataLine = null;
    }
    return items;
  }

  Map<String, String> _attributes(String line) {
    final result = <String, String>{};
    for (final match in _attributePattern.allMatches(line)) {
      result[match.group(1)!] = match.group(2) ?? match.group(3) ?? '';
    }
    return result;
  }

  Map<String, String> _retain(Map<String, String> attributes) {
    Map<String, String>? retained;
    for (final key in _retainedAttributes) {
      final value = attributes[key];
      if (value == null) continue;
      (retained ??= <String, String>{})[key] = value;
    }
    return retained ?? const <String, String>{};
  }

  String? _first(Map<String, String> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  ContentType _contentType(
    Map<String, String> attributes,
    String group,
    String url,
  ) {
    // Tested piece by piece instead of concatenated into one lowercased
    // string: the hints are whole words, so they can never straddle two
    // pieces, and this avoids a long throwaway allocation per entry.
    for (final candidate in [
      attributes['type'],
      attributes['content-type'],
      group,
      url,
    ]) {
      if (candidate == null || candidate.isEmpty) continue;
      if (_contentTypeHintPattern.hasMatch(candidate.toLowerCase())) {
        return ContentType.vod;
      }
    }
    return ContentType.live;
  }

  String _resolveUrl(String value, String? sourceUrl) {
    if (sourceUrl == null || _hasScheme(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    return Uri.parse(sourceUrl).resolve(value).toString();
  }

  /// Cheap `scheme:` probe so absolute URLs — the overwhelming majority of
  /// playlist entries — skip a full [Uri] parse.
  static bool _hasScheme(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      final isAlpha =
          (unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a);
      if (i == 0) {
        if (!isAlpha) return false;
        continue;
      }
      if (unit == 0x3a) return true;
      final isDigit = unit >= 0x30 && unit <= 0x39;
      if (!isAlpha &&
          !isDigit &&
          unit != 0x2b &&
          unit != 0x2d &&
          unit != 0x2e) {
        return false;
      }
    }
    return false;
  }
}
