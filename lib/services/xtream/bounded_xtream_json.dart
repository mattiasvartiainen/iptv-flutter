import 'dart:convert';

const maxXtreamJsonNodes = 100000;
const maxXtreamJsonDepth = 64;
const maxXtreamJsonStringBytes = 256 * 1024;

class XtreamJsonLimitException implements Exception {
  const XtreamJsonLimitException();
}

Object? decodeBoundedXtreamJson(List<int> bytes) {
  var nodes = 0;
  var depth = 0;
  var inString = false;
  var escaped = false;
  var stringBytes = 0;
  var inScalar = false;
  // Check allocation-driving structure before creating the UTF-16 text/JSON graph.
  for (final byte in bytes) {
    if (inString) {
      if (!escaped && byte == 34) {
        inString = false;
        continue;
      }
      if (++stringBytes > maxXtreamJsonStringBytes) {
        throw const XtreamJsonLimitException();
      }
      if (escaped) {
        escaped = false;
      } else if (byte == 92) {
        escaped = true;
      }
      continue;
    }
    if (byte == 34) {
      inString = true;
      stringBytes = 0;
      inScalar = false;
      nodes++;
    } else if (byte == 123 || byte == 91) {
      depth++;
      nodes++;
      inScalar = false;
      if (depth > maxXtreamJsonDepth) {
        throw const XtreamJsonLimitException();
      }
    } else if (byte == 125 || byte == 93) {
      depth--;
      inScalar = false;
    } else if (byte == 44 || byte == 58 || byte <= 32) {
      inScalar = false;
    } else if (!inScalar) {
      nodes++;
      inScalar = true;
    }
    if (nodes > maxXtreamJsonNodes) {
      throw const XtreamJsonLimitException();
    }
  }
  return jsonDecode(utf8.decode(bytes));
}
