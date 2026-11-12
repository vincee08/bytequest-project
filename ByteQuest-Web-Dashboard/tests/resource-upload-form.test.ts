import assert from "node:assert/strict";
import { test } from "node:test";
import {
  readResourceForm,
  UploadSizeError,
} from "../src/lib/resources/upload-form";
test("streamed multipart retains a valid file and metadata", async () => {
  const body = new FormData();
  body.set("title", "PDF review");
  body.set(
    "file",
    new File(["%PDF-1.4"], "review.pdf", { type: "application/pdf" }),
  );
  const form = await readResourceForm(
    new Request("http://local.invalid", { method: "POST", body }),
  );
  assert.equal(form.get("title"), "PDF review");
  assert.equal((form.get("file") as File).type, "application/pdf");
});
test("unknown-length uploads cannot bypass the body limit", async () => {
  const request = new Request("http://local.invalid", {
    method: "POST",
    body: "X".repeat(2000),
    headers: { "Content-Type": "multipart/form-data; boundary=qa" },
  });
  await assert.rejects(readResourceForm(request, 1000), UploadSizeError);
});
test("oversized declared body is rejected before reading it", async () => {
  await assert.rejects(
    readResourceForm(
      new Request("http://local.invalid", {
        method: "POST",
        body: "unused",
        headers: { "Content-Length": "2000" },
      }),
      1000,
    ),
    UploadSizeError,
  );
});
