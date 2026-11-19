/**
 * Safe Markdown subset for curriculum lessons. Lessons are stored as Markdown
 * and rendered as plain React elements (never as HTML), so raw HTML in a
 * lesson is shown as text. The learner app renders the same subset.
 *
 * Blocks: #/##/### headings, paragraphs, "- " / "* " bullets, "1. " numbered
 * lists, "> " quotes and ``` code fences. Inline: **bold**, *italic* or
 * _italic_, `code`, and [label](url) shown as "label (url)".
 */
export type MdInline = { kind: 'text' | 'strong' | 'em' | 'code'; text: string };
export type MdBlock =
  | { type: 'heading'; level: 1 | 2 | 3; inlines: MdInline[] }
  | { type: 'paragraph'; inlines: MdInline[] }
  | { type: 'list'; ordered: boolean; items: MdInline[][] }
  | { type: 'quote'; inlines: MdInline[] }
  | { type: 'code'; text: string };

const INLINE = /(\*\*[^*]+\*\*|`[^`]+`|\*[^*\s][^*]*\*|_[^_\s][^_]*_|\[[^\]]+\]\([^)\s]+\))/g;

export function parseInline(source: string): MdInline[] {
  const result: MdInline[] = [];
  let last = 0;
  for (const match of source.matchAll(INLINE)) {
    const token = match[0];
    const index = match.index ?? 0;
    if (index > last) result.push({ kind: 'text', text: source.slice(last, index) });
    if (token.startsWith('**')) result.push({ kind: 'strong', text: token.slice(2, -2) });
    else if (token.startsWith('`')) result.push({ kind: 'code', text: token.slice(1, -1) });
    else if (token.startsWith('[')) {
      const split = token.indexOf('](');
      result.push({ kind: 'text', text: `${token.slice(1, split)} (${token.slice(split + 2, -1)})` });
    } else result.push({ kind: 'em', text: token.slice(1, -1) });
    last = index + token.length;
  }
  if (last < source.length) result.push({ kind: 'text', text: source.slice(last) });
  return result.filter((part) => part.text.length > 0);
}

export function parseMarkdown(source: string): MdBlock[] {
  const lines = source.replace(/\r\n?/g, '\n').split('\n');
  const blocks: MdBlock[] = [];
  const state: { paragraph: string[]; list: { ordered: boolean; items: MdInline[][] } | null } = { paragraph: [], list: null };

  const flushParagraph = () => {
    if (state.paragraph.length) blocks.push({ type: 'paragraph', inlines: parseInline(state.paragraph.join(' ')) });
    state.paragraph = [];
  };
  const flushList = () => {
    if (state.list) blocks.push({ type: 'list', ordered: state.list.ordered, items: state.list.items });
    state.list = null;
  };

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      flushParagraph();
      flushList();
      const code: string[] = [];
      i += 1;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        code.push(lines[i]);
        i += 1;
      }
      blocks.push({ type: 'code', text: code.join('\n') });
      continue;
    }
    if (!trimmed) {
      flushParagraph();
      flushList();
      continue;
    }
    const heading = /^(#{1,6})\s+(.*)$/.exec(trimmed);
    if (heading) {
      flushParagraph();
      flushList();
      blocks.push({ type: 'heading', level: Math.min(heading[1].length, 3) as 1 | 2 | 3, inlines: parseInline(heading[2]) });
      continue;
    }
    const bullet = /^[-*+]\s+(.*)$/.exec(trimmed);
    const numbered = /^\d+[.)]\s+(.*)$/.exec(trimmed);
    const item = bullet ?? numbered;
    if (item) {
      flushParagraph();
      const ordered = Boolean(numbered);
      if (!state.list || state.list.ordered !== ordered) flushList();
      const target = state.list ?? { ordered, items: [] };
      target.items.push(parseInline(item[1]));
      state.list = target;
      continue;
    }
    if (trimmed.startsWith('>')) {
      flushParagraph();
      flushList();
      blocks.push({ type: 'quote', inlines: parseInline(trimmed.replace(/^>\s?/, '')) });
      continue;
    }
    flushList();
    state.paragraph.push(trimmed);
  }
  flushParagraph();
  flushList();
  return blocks;
}
