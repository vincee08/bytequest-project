import React, { Fragment } from "react";
import { parseMarkdown, type MdInline } from "@/lib/curriculum/markdown";

function Inline({ parts }: { parts: MdInline[] }) {
  return (
    <>
      {parts.map((part, index) => {
        if (part.kind === "strong") return <strong key={index}>{part.text}</strong>;
        if (part.kind === "em") return <em key={index}>{part.text}</em>;
        if (part.kind === "code")
          return (
            <code key={index} className="rounded bg-muted px-1 py-0.5 font-mono text-[0.85em]">
              {part.text}
            </code>
          );
        return <Fragment key={index}>{part.text}</Fragment>;
      })}
    </>
  );
}

/** Renders lesson Markdown as plain React elements (never as HTML), exactly the subset the learner app shows. */
export function MarkdownPreview({ source, emptyLabel = "Nothing to preview yet." }: { source: string; emptyLabel?: string }) {
  const blocks = parseMarkdown(source);
  if (!blocks.length) return <p className="text-sm text-muted-foreground">{emptyLabel}</p>;
  return (
    <div className="space-y-3 text-sm leading-6 text-foreground">
      {blocks.map((block, index) => {
        switch (block.type) {
          case "heading": {
            const className = block.level === 1 ? "text-lg font-bold" : block.level === 2 ? "text-base font-bold" : "text-sm font-bold";
            const Tag = block.level === 1 ? "h3" : block.level === 2 ? "h4" : "h5";
            return (
              <Tag key={index} className={className}>
                <Inline parts={block.inlines} />
              </Tag>
            );
          }
          case "list": {
            const Tag = block.ordered ? "ol" : "ul";
            return (
              <Tag key={index} className={block.ordered ? "list-decimal space-y-1 pl-5" : "list-disc space-y-1 pl-5"}>
                {block.items.map((item, itemIndex) => (
                  <li key={itemIndex}>
                    <Inline parts={item} />
                  </li>
                ))}
              </Tag>
            );
          }
          case "quote":
            return (
              <blockquote key={index} className="border-l-4 border-primary/40 bg-primary/[0.04] px-3 py-2">
                <Inline parts={block.inlines} />
              </blockquote>
            );
          case "code":
            return (
              <pre key={index} className="overflow-x-auto rounded-lg bg-muted p-3 font-mono text-xs">
                {block.text}
              </pre>
            );
          default:
            return (
              <p key={index}>
                <Inline parts={block.inlines} />
              </p>
            );
        }
      })}
    </div>
  );
}
