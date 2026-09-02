import 'dart:convert';

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

  List<ContentItem> parse(String text, {String? sourceUrl}) {
    final lines = const LineSplitter().convert(text);
    final items = <ContentItem>[];
    String? metadataLine;

    for (final rawLine in lines) {
      final line = rawLine.trim();
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
          metadata: Map.unmodifiable(attributes),
          sourceIndex: items.length,
        ),
      );
      metadataLine = null;
    }
    return List.unmodifiable(items);
  }

  Map<String, String> _attributes(String line) {
    final result = <String, String>{};
    for (final match in _attributePattern.allMatches(line)) {
      result[match.group(1)!] = match.group(2) ?? match.group(3) ?? '';
    }
    return result;
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
    final hint =
        '${attributes['type'] ?? ''} ${attributes['content-type'] ?? ''} $group $url'
            .toLowerCase();
    return _contentTypeHintPattern.hasMatch(hint)
        ? ContentType.vod
        : ContentType.live;
  }

  String _resolveUrl(String value, String? sourceUrl) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.hasScheme || sourceUrl == null) return value;
    return Uri.parse(sourceUrl).resolve(value).toString();
  }
}
