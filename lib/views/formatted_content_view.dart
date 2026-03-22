import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'content_formatter.dart';

/// Renders [FormattedContent] with nice typography:
/// - Plain text as normal body text
/// - JSON in a scrollable, monospace container with copy button
/// - Key-value maps as a compact card
class FormattedContentView extends StatelessWidget {
  const FormattedContentView({
    super.key,
    required this.content,
    this.maxJsonLines = 20,
  });

  final FormattedContent content;

  /// JSON blocks taller than this are collapsed behind a "Show more" toggle.
  final int maxJsonLines;

  @override
  Widget build(BuildContext context) {
    if (content.isPlainText) {
      return _ExpandableText(text: content.segments.first.text ?? '');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segment in content.segments) ...[
          _buildSegment(context, segment),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildSegment(BuildContext context, ContentSegment segment) {
    switch (segment.type) {
      case SegmentType.text:
        return _ExpandableText(text: segment.text ?? '');
      case SegmentType.json:
        return _JsonBlock(
          json: segment.jsonText ?? '',
          maxLines: maxJsonLines,
        );
      case SegmentType.keyValue:
        return _KeyValueCard(pairs: segment.kvPairs ?? {});
    }
  }
}

// ─── Expandable text ─────────────────────────────────────────────────────────

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});
  final String text;
  static const int maxLines = 6;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(
          text: widget.text,
          style: theme.textTheme.bodyMedium,
        );
        final tp = TextPainter(
          text: span,
          maxLines: _ExpandableText.maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        if (!tp.didExceedMaxLines) {
          return Text(widget.text, style: theme.textTheme.bodyMedium);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: theme.textTheme.bodyMedium,
              maxLines: _expanded ? null : _ExpandableText.maxLines,
              overflow: _expanded ? null : TextOverflow.fade,
            ),
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(_expanded ? 'Show less' : 'Show more'),
              style: TextButton.styleFrom(
                textStyle: theme.textTheme.labelSmall,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── JSON block with copy + collapse ─────────────────────────────────────────

class _JsonBlock extends StatefulWidget {
  const _JsonBlock({required this.json, this.maxLines = 20});
  final String json;
  final int maxLines;

  @override
  State<_JsonBlock> createState() => _JsonBlockState();
}

class _JsonBlockState extends State<_JsonBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = widget.json.split('\n');
    final needsCollapse = lines.length > widget.maxLines;
    final displayText = (!_expanded && needsCollapse)
        ? '${lines.take(widget.maxLines).join('\n')}\n  …'
        : widget.json;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(120),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toolbar row
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 6),
                child: Icon(
                  Icons.data_object,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 6),
                child: Text(
                  'JSON',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              _CopyButton(text: widget.json),
            ],
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                displayText,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (needsCollapse)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(_expanded ? 'Show less' : 'Show more'),
                style: TextButton.styleFrom(
                  textStyle: theme.textTheme.labelSmall,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Copy button ─────────────────────────────────────────────────────────────

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _copied ? Icons.check : Icons.copy,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      tooltip: 'Copy',
      iconSize: 16,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(4),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.text));
        if (mounted) {
          setState(() => _copied = true);
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _copied = false);
          });
        }
      },
    );
  }
}

// ─── Key-value card ──────────────────────────────────────────────────────────

class _KeyValueCard extends StatelessWidget {
  const _KeyValueCard({required this.pairs});
  final Map<String, dynamic> pairs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(120),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in pairs.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      entry.key,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _valueToString(entry.value),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _valueToString(dynamic value) {
    if (value == null) return '—';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    // For nested objects, show compact JSON.
    try {
      return const JsonEncoder().convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}
