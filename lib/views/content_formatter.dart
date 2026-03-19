import 'dart:convert';

/// Classifies and extracts displayable content from backend messages.
///
/// Backend messages can arrive as plain text, JSON objects with a `text` key,
/// nested `{text: {content: "..."}}`, tool results, or raw JSON blobs.
/// This class normalises all of those into a [FormattedContent] that the UI
/// can render in a structured way.
class ContentFormatter {
  const ContentFormatter._();

  /// Analyse raw message content and return a structured representation.
  static FormattedContent format(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const FormattedContent(segments: [
        ContentSegment.text('(no content)'),
      ]);
    }

    final trimmed = raw.trim();

    // ── Try JSON parsing ────────────────────────────────────────────────
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final decoded = const JsonDecoder().convert(trimmed);
        return _fromDecoded(decoded, trimmed);
      } catch (_) {
        // Not valid JSON — fall through to plain text.
      }
    }

    // ── Plain text (may still contain embedded JSON fragments) ──────────
    return _maybeWithEmbeddedJson(trimmed);
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  static FormattedContent _fromDecoded(dynamic decoded, String raw) {
    if (decoded is Map<String, dynamic>) {
      return _fromMap(decoded, raw);
    }
    if (decoded is List) {
      return _fromList(decoded, raw);
    }
    // Scalar JSON value — just show as text.
    return FormattedContent(segments: [ContentSegment.text(decoded.toString())]);
  }

  static FormattedContent _fromMap(Map<String, dynamic> map, String raw) {
    // {text: "actual message"} — common wrapper
    if (map.containsKey('text')) {
      final text = map['text'];
      if (text is String) {
        // The inner text might itself be JSON.
        return format(text);
      }
      if (text is Map<String, dynamic> && text.containsKey('content')) {
        final inner = text['content'];
        if (inner is String) return format(inner);
      }
    }

    // {toolResult: {content: [{text: "..."}]}} — tool output
    if (map.containsKey('toolResult')) {
      return _formatToolResult(map['toolResult']);
    }

    // Generic key-value map — render as a card with key/value pairs.
    // If it's small (≤ 6 keys) show as key-value, otherwise show as
    // pretty-printed JSON.
    if (map.length <= 6) {
      return FormattedContent(segments: [ContentSegment.keyValue(map)]);
    }
    return FormattedContent(segments: [
      ContentSegment.json(_prettyJson(map)),
    ]);
  }

  static FormattedContent _fromList(List list, String raw) {
    if (list.isEmpty) {
      return const FormattedContent(segments: [ContentSegment.text('(empty list)')]);
    }
    // Short list of scalars — show inline.
    if (list.length <= 5 && list.every((e) => e is! Map && e is! List)) {
      return FormattedContent(segments: [
        ContentSegment.text(list.join(', ')),
      ]);
    }
    return FormattedContent(segments: [
      ContentSegment.json(_prettyJson(list)),
    ]);
  }

  static FormattedContent _formatToolResult(dynamic toolResult) {
    if (toolResult is! Map<String, dynamic>) {
      return FormattedContent(segments: [
        ContentSegment.json(_prettyJson(toolResult)),
      ]);
    }
    final items = toolResult['content'] as List?;
    if (items == null || items.isEmpty) {
      return const FormattedContent(segments: [
        ContentSegment.text('(empty tool result)'),
      ]);
    }
    final segments = <ContentSegment>[];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final text = item['text'] as String?;
        if (text != null) {
          // Tool text might itself be JSON.
          final inner = format(text);
          segments.addAll(inner.segments);
        } else {
          segments.add(ContentSegment.json(_prettyJson(item)));
        }
      }
    }
    if (segments.isEmpty) {
      return FormattedContent(segments: [
        ContentSegment.json(_prettyJson(toolResult)),
      ]);
    }
    return FormattedContent(segments: segments);
  }

  /// Scans plain text for embedded JSON blocks (e.g. `some text {"key":"val"} more text`).
  static FormattedContent _maybeWithEmbeddedJson(String text) {
    final segments = <ContentSegment>[];
    final buffer = StringBuffer();
    var i = 0;

    while (i < text.length) {
      if (text[i] == '{' || text[i] == '[') {
        final jsonStr = _extractJsonAt(text, i);
        if (jsonStr != null) {
          // Flush preceding plain text.
          if (buffer.isNotEmpty) {
            segments.add(ContentSegment.text(buffer.toString()));
            buffer.clear();
          }
          try {
            final decoded = const JsonDecoder().convert(jsonStr);
            segments.add(ContentSegment.json(_prettyJson(decoded)));
          } catch (_) {
            segments.add(ContentSegment.json(jsonStr));
          }
          i += jsonStr.length;
          continue;
        }
      }
      buffer.write(text[i]);
      i++;
    }
    if (buffer.isNotEmpty) {
      segments.add(ContentSegment.text(buffer.toString()));
    }
    if (segments.isEmpty) {
      return FormattedContent(segments: [ContentSegment.text(text)]);
    }
    return FormattedContent(segments: segments);
  }

  /// Tries to extract a balanced JSON object/array starting at [start].
  /// Returns the substring if valid JSON, otherwise null.
  static String? _extractJsonAt(String text, int start) {
    final open = text[start];
    final close = open == '{' ? '}' : ']';
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\' && inString) {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == open) depth++;
      if (c == close) depth--;
      if (depth == 0) {
        final candidate = text.substring(start, i + 1);
        // Quick validation — must parse.
        try {
          const JsonDecoder().convert(candidate);
          return candidate;
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  static String _prettyJson(dynamic obj) {
    return const JsonEncoder.withIndent('  ').convert(obj);
  }
}

/// The result of formatting a message — a list of typed segments.
class FormattedContent {
  const FormattedContent({required this.segments});
  final List<ContentSegment> segments;

  /// Convenience: true when the content is a single plain-text segment.
  bool get isPlainText =>
      segments.length == 1 && segments.first.type == SegmentType.text;
}

enum SegmentType { text, json, keyValue }

/// A single piece of formatted content.
class ContentSegment {
  const ContentSegment.text(this.text)
      : type = SegmentType.text,
        jsonText = null,
        kvPairs = null;

  const ContentSegment.json(String json)
      : type = SegmentType.json,
        jsonText = json,
        text = null,
        kvPairs = null;

  const ContentSegment.keyValue(Map<String, dynamic> pairs)
      : type = SegmentType.keyValue,
        kvPairs = pairs,
        text = null,
        jsonText = null;

  final SegmentType type;
  final String? text;
  final String? jsonText;
  final Map<String, dynamic>? kvPairs;
}
