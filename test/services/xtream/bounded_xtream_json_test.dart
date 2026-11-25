import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/xtream/bounded_xtream_json.dart';

void main() {
  Object? decode(String text) => decodeBoundedXtreamJson(utf8.encode(text));
  test('ordinary JSON and escaped delimiters retain their values', () {
    final payload = {
      'plot': 'Unicode \u00e5; \\"[{]}',
      'n': [true, false, null, 42],
    };
    expect(decode(jsonEncode(payload)), payload);
  });
  test('node threshold is exact including containers and keys', () {
    final atLimit = '[${List.filled(maxXtreamJsonNodes - 1, '0').join(',')}]';
    expect(decode(atLimit), hasLength(maxXtreamJsonNodes - 1));
    expect(
      () => decode('[${List.filled(maxXtreamJsonNodes, '0').join(',')}]'),
      throwsA(isA<XtreamJsonLimitException>()),
    );
  });
  test('depth threshold is exact and ignores braces inside strings', () {
    final nested = '${'[' * maxXtreamJsonDepth}0${']' * maxXtreamJsonDepth}';
    expect(decode(nested), isA<List>());
    expect(() => decode('[$nested]'), throwsA(isA<XtreamJsonLimitException>()));
    expect(decode(jsonEncode('[' * 1000)), '[' * 1000);
  });
  test('single string allocations are bounded by UTF-8 bytes', () {
    expect(
      decode(jsonEncode('x' * maxXtreamJsonStringBytes)),
      hasLength(maxXtreamJsonStringBytes),
    );
    expect(
      () => decode(jsonEncode('x' * (maxXtreamJsonStringBytes + 1))),
      throwsA(isA<XtreamJsonLimitException>()),
    );
    expect(
      () => decode(jsonEncode('\u00e5' * (maxXtreamJsonStringBytes ~/ 2 + 1))),
      throwsA(isA<XtreamJsonLimitException>()),
    );
  });
  test('malformed JSON remains a parse error', () {
    expect(() => decode('{"plot":'), throwsFormatException);
  });
}
