import assert from "node:assert/strict";
import { test } from "node:test";
import { textPdf, manyPagesPdf } from "../../scripts/fixtures/resource-pdf.mjs";
import { extractResourcePdf } from "../src/lib/resources/pdf";
import { matchesResourceContent } from "../src/lib/resources/policy";

test("extracts synthetic PDF text with bounded processing", async () => {
  const result = await extractResourcePdf(textPdf());
  assert.match(result.text, /router connects different IP networks/);
  assert.equal(result.pages, 1);
});
test("rejects forged, corrupted, empty and scanned PDFs without provider access", async () => {
  await assert.rejects(
    extractResourcePdf(Buffer.from("not a PDF")),
    /PDF_INVALID/,
  );
  await assert.rejects(
    extractResourcePdf(Buffer.from("%PDF-1.4\ncorrupted\n%%EOF")),
    /PDF_INVALID/,
  );
  await assert.rejects(extractResourcePdf(textPdf("")), /PDF_NO_TEXT/);
  await assert.rejects(
    extractResourcePdf(Buffer.alloc(10 * 1024 * 1024 + 1)),
    /PDF_TOO_LARGE/,
  );
});
test("checks actual content signatures for every supported upload type", () => {
  assert(matchesResourceContent("application/pdf", textPdf()));
  assert(!matchesResourceContent("application/pdf", Buffer.from("<script>")));
  assert(
    matchesResourceContent("image/jpeg", Buffer.from([255, 216, 255, 224])),
  );
  assert(
    matchesResourceContent(
      "image/png",
      Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    ),
  );
  assert(matchesResourceContent("image/webp", Buffer.from("RIFF0000WEBP")));
  assert(matchesResourceContent("video/mp4", Buffer.from("0000ftypisom")));
  assert(matchesResourceContent("video/webm", Buffer.from([26, 69, 223, 163])));
  assert(!matchesResourceContent("image/png", textPdf()));
  assert(!matchesResourceContent("application/pdf", Buffer.alloc(0)));
});

test("rejects encrypted and overlong PDFs with specific safe errors", async () => {
  const pdf = textPdf().toString();
  const encrypted = pdf.replace(
    "/Size 6 /Root 1 0 R",
    `/Size 6 /Root 1 0 R /Encrypt << /Filter /Standard /V 1 /R 2 /P -4 /O <${"00".repeat(32)}> /U <${"11".repeat(32)}> >> /ID [<${"22".repeat(16)}> <${"22".repeat(16)}>]`,
  );
  await assert.rejects(
    extractResourcePdf(Buffer.from(encrypted)),
    /PDF_ENCRYPTED/,
  );
  await assert.rejects(extractResourcePdf(manyPagesPdf()), /PDF_TOO_LONG/);
  await assert.rejects(
    extractResourcePdf(textPdf("Router networks. ".repeat(4000))),
    /PDF_TOO_LONG/,
  );
});
