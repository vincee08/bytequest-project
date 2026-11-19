import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Renders the lesson Markdown subset shared with the dashboard preview:
/// #/##/### headings, paragraphs, "- " bullets, "1. " numbered lists, "> "
/// quotes, ``` code fences, **bold**, *italic*/_italic_, `code` and
/// [label](url) shown as text. Content is never interpreted as HTML.
class LessonMarkdown extends StatelessWidget {
  const LessonMarkdown({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final blocks = parseLessonMarkdown(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _block(block),
          ),
      ],
    );
  }

  Widget _block(LessonBlock block) {
    switch (block.type) {
      case LessonBlockType.heading:
        final style = block.level == 1
            ? AppTheme.headlineSmall
            : block.level == 2
                ? AppTheme.titleLarge
                : AppTheme.titleMedium;
        return Semantics(
          header: true,
          child: Text.rich(_spans(block.inlines.first,
              style.copyWith(fontWeight: FontWeight.w800))),
        );
      case LessonBlockType.paragraph:
        return Text.rich(_spans(
            block.inlines.first, AppTheme.bodyMedium.copyWith(height: 1.5)));
      case LessonBlockType.quote:
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: const BoxDecoration(
            color: AppTheme.backgroundPaleBlue,
            border:
                Border(left: BorderSide(color: AppTheme.primaryBlue, width: 3)),
          ),
          child: Text.rich(_spans(
              block.inlines.first, AppTheme.bodyMedium.copyWith(height: 1.5))),
        );
      case LessonBlockType.code:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(block.code,
                style: AppTheme.bodySmall.copyWith(fontFamily: 'monospace')),
          ),
        );
      case LessonBlockType.list:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < block.inlines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(block.ordered ? '${i + 1}.' : '•',
                          style: AppTheme.bodyMedium
                              .copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                        child: Text.rich(_spans(block.inlines[i],
                            AppTheme.bodyMedium.copyWith(height: 1.5)))),
                  ],
                ),
              ),
          ],
        );
    }
  }

  TextSpan _spans(List<LessonInline> inlines, TextStyle base) => TextSpan(
        style: base,
        children: [
          for (final part in inlines)
            TextSpan(
              text: part.text,
              style: switch (part.kind) {
                LessonInlineKind.strong =>
                  const TextStyle(fontWeight: FontWeight.w800),
                LessonInlineKind.em =>
                  const TextStyle(fontStyle: FontStyle.italic),
                LessonInlineKind.code => const TextStyle(
                    fontFamily: 'monospace',
                    backgroundColor: AppTheme.surfaceMuted,
                    color: AppTheme.textDark),
                LessonInlineKind.text => null,
              },
            ),
        ],
      );
}

enum LessonBlockType { heading, paragraph, list, quote, code }

enum LessonInlineKind { text, strong, em, code }

class LessonInline {
  const LessonInline(this.kind, this.text);
  final LessonInlineKind kind;
  final String text;
}

class LessonBlock {
  const LessonBlock(this.type,
      {this.level = 0,
      this.ordered = false,
      this.inlines = const [],
      this.code = ''});
  final LessonBlockType type;
  final int level;
  final bool ordered;

  /// One inline run for headings, paragraphs and quotes; one per list item.
  final List<List<LessonInline>> inlines;
  final String code;
}

final _inline = RegExp(
    r'(\*\*[^*]+\*\*|`[^`]+`|\*[^*\s][^*]*\*|_[^_\s][^_]*_|\[[^\]]+\]\([^)\s]+\))');

List<LessonInline> parseLessonInline(String source) {
  final result = <LessonInline>[];
  var last = 0;
  for (final match in _inline.allMatches(source)) {
    if (match.start > last) {
      result.add(LessonInline(
          LessonInlineKind.text, source.substring(last, match.start)));
    }
    final token = match.group(0)!;
    if (token.startsWith('**')) {
      result.add(LessonInline(
          LessonInlineKind.strong, token.substring(2, token.length - 2)));
    } else if (token.startsWith('`')) {
      result.add(LessonInline(
          LessonInlineKind.code, token.substring(1, token.length - 1)));
    } else if (token.startsWith('[')) {
      final split = token.indexOf('](');
      result.add(LessonInline(LessonInlineKind.text,
          '${token.substring(1, split)} (${token.substring(split + 2, token.length - 1)})'));
    } else {
      result.add(LessonInline(
          LessonInlineKind.em, token.substring(1, token.length - 1)));
    }
    last = match.end;
  }
  if (last < source.length) {
    result.add(LessonInline(LessonInlineKind.text, source.substring(last)));
  }
  return result.where((part) => part.text.isNotEmpty).toList(growable: false);
}

List<LessonBlock> parseLessonMarkdown(String source) {
  final lines =
      source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final blocks = <LessonBlock>[];
  var paragraph = <String>[];
  List<List<LessonInline>>? listItems;
  var listOrdered = false;

  void flushParagraph() {
    if (paragraph.isNotEmpty) {
      blocks.add(LessonBlock(LessonBlockType.paragraph,
          inlines: [parseLessonInline(paragraph.join(' '))]));
    }
    paragraph = [];
  }

  void flushList() {
    final items = listItems;
    if (items != null && items.isNotEmpty) {
      blocks.add(LessonBlock(LessonBlockType.list,
          ordered: listOrdered, inlines: items));
    }
    listItems = null;
  }

  final heading = RegExp(r'^(#{1,6})\s+(.*)$');
  final bullet = RegExp(r'^[-*+]\s+(.*)$');
  final numbered = RegExp(r'^\d+[.)]\s+(.*)$');
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (trimmed.startsWith('```')) {
      flushParagraph();
      flushList();
      final code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        code.add(lines[i]);
        i++;
      }
      blocks.add(LessonBlock(LessonBlockType.code, code: code.join('\n')));
      continue;
    }
    if (trimmed.isEmpty) {
      flushParagraph();
      flushList();
      continue;
    }
    final headingMatch = heading.firstMatch(trimmed);
    if (headingMatch != null) {
      flushParagraph();
      flushList();
      final level = headingMatch.group(1)!.length.clamp(1, 3);
      blocks.add(LessonBlock(LessonBlockType.heading,
          level: level, inlines: [parseLessonInline(headingMatch.group(2)!)]));
      continue;
    }
    final item = bullet.firstMatch(trimmed) ?? numbered.firstMatch(trimmed);
    if (item != null) {
      flushParagraph();
      final ordered = numbered.hasMatch(trimmed) && !bullet.hasMatch(trimmed);
      if (listItems == null || listOrdered != ordered) {
        flushList();
        listItems = [];
        listOrdered = ordered;
      }
      listItems!.add(parseLessonInline(item.group(1)!));
      continue;
    }
    if (trimmed.startsWith('>')) {
      flushParagraph();
      flushList();
      blocks.add(LessonBlock(LessonBlockType.quote, inlines: [
        parseLessonInline(trimmed.replaceFirst(RegExp(r'^>\s?'), ''))
      ]));
      continue;
    }
    flushList();
    paragraph.add(trimmed);
  }
  flushParagraph();
  flushList();
  return blocks;
}
