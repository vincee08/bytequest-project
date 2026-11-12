import "server-only";
import path from "node:path";
import { Worker } from "node:worker_threads";

export const MAX_AI_PDF_BYTES = 10 * 1024 * 1024;
export class ResourcePdfError extends Error {
  constructor(public readonly code: string) {
    super(code);
  }
}
export const pdfErrorMessages: Record<string, string> = {
  PDF_TOO_LARGE:
    "AI reading supports PDFs up to 10 MB. Upload a shorter excerpt; class uploads still support 50 MB.",
  PDF_TOO_LONG:
    "Use a PDF with at most 50 pages and 48,000 text characters for AI generation.",
  PDF_ENCRYPTED:
    "This PDF is encrypted. Upload an unencrypted copy that you are authorized to use.",
  PDF_NO_TEXT:
    "No usable text was found. Scanned or image-only PDFs need OCR first; OCR is not supported here.",
  PDF_INVALID:
    "This PDF could not be read. It may be corrupted or unsupported. Export a text-based PDF and try again.",
  PDF_TIMEOUT:
    "PDF processing exceeded its safety limit. Try a smaller, simpler PDF.",
  PDF_BUSY: "Document processing is busy. Wait briefly and try again.",
};
let active = 0;
export async function extractResourcePdf(
  bytes: Uint8Array,
): Promise<{ text: string; pages: number }> {
  if (bytes.byteLength > MAX_AI_PDF_BYTES)
    throw new ResourcePdfError("PDF_TOO_LARGE");
  if (Buffer.from(bytes.subarray(0, 5)).toString() !== "%PDF-")
    throw new ResourcePdfError("PDF_INVALID");
  if (active >= 2) throw new ResourcePdfError("PDF_BUSY");
  active++;
  try {
    return await new Promise((resolve, reject) => {
      const worker = new Worker(
        path.join(process.cwd(), "src/lib/resources/pdf-worker.mjs"),
        {
          workerData: { bytes },
          env: {},
          resourceLimits: {
            maxOldGenerationSizeMb: 192,
            maxYoungGenerationSizeMb: 32,
            stackSizeMb: 4,
          },
          // Parser diagnostics may contain document content. Never forward them.
          stdout: true,
          stderr: true,
        },
      );
      worker.stdout.resume();
      worker.stderr.resume();
      const timer = setTimeout(() => {
        void worker.terminate();
        reject(new ResourcePdfError("PDF_TIMEOUT"));
      }, 15_000);
      worker.once(
        "message",
        (message: { text?: string; pages?: number; error?: string }) => {
          clearTimeout(timer);
          void worker.terminate();
          if (message.error || !message.text || !message.pages)
            reject(new ResourcePdfError(message.error ?? "PDF_INVALID"));
          else resolve({ text: message.text, pages: message.pages });
        },
      );
      worker.once("error", () => {
        clearTimeout(timer);
        reject(new ResourcePdfError("PDF_INVALID"));
      });
      worker.once("exit", (code) => {
        clearTimeout(timer);
        if (code !== 0) reject(new ResourcePdfError("PDF_INVALID"));
      });
    });
  } finally {
    active--;
  }
}
