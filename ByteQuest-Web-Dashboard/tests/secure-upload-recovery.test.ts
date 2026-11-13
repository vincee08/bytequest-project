import assert from "node:assert/strict";
import { test } from "node:test";
import { createHash, randomBytes } from "node:crypto";
import { duplicateStorageUpload } from "../src/lib/uploads/client";
import { recoveryProof, validRecoveryProof } from "../src/lib/auth/recovery";
import {
  smallJson,
  verifyUploadedFile,
  InvalidUploadedFile,
  type UploadIntent,
} from "../src/lib/uploads/server";

test("Storage duplicate retries accept the supported 400 response without masking unrelated failures", () => {
  const duplicate = JSON.stringify({
    statusCode: "409",
    code: "KeyAlreadyExists",
    error: "Duplicate",
  });
  assert(duplicateStorageUpload(400, duplicate));
  assert(duplicateStorageUpload(409, "{}"));
  assert(!duplicateStorageUpload(400, "not json"));
  assert(!duplicateStorageUpload(400, '{"error":"InvalidMimeType"}'));
  assert(!duplicateStorageUpload(403, duplicate));
});

test("recovery proof binds the verified user/session and expires after fifteen minutes", () => {
  const before = process.env.SUPABASE_SERVICE_ROLE_KEY;
  process.env.SUPABASE_SERVICE_ROLE_KEY = randomBytes(32).toString("hex");
  try {
    const now = 1800000000000,
      proof = recoveryProof("user-a", "session-a", now);
    assert(validRecoveryProof(proof, "user-a", "session-a", now));
    assert(!validRecoveryProof(proof, "user-b", "session-a", now));
    assert(!validRecoveryProof(proof, "user-a", "session-b", now));
    assert(!validRecoveryProof(proof + "tampered", "user-a", "session-a", now));
    assert(!validRecoveryProof(proof, "user-a", "session-a", now + 900000));
    process.env.SUPABASE_SERVICE_ROLE_KEY = randomBytes(32).toString("hex");
    assert(!validRecoveryProof(proof, "user-a", "session-a", now));
  } finally {
    if (before === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    else process.env.SUPABASE_SERVICE_ROLE_KEY = before;
  }
});
test("upload/recovery metadata bodies are capped before JSON parsing", async () => {
  assert.deepEqual(
    await smallJson(
      new Request("https://qa.invalid", {
        method: "POST",
        body: '{"action":"prepare"}',
      }),
    ),
    { action: "prepare" },
  );
  await assert.rejects(
    smallJson(
      new Request("https://qa.invalid", {
        method: "POST",
        body: "x".repeat(8193),
      }),
    ),
    /BODY_TOO_LARGE/,
  );
});
test("stream verification rejects changed bytes, MIME, size, invalid UTF-8 and non-Storage origins", async () => {
  const previousFetch = global.fetch,
    previousUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  process.env.NEXT_PUBLIC_SUPABASE_URL = "https://storage.qa.invalid";
  let content = Buffer.from("%PDF-1.4\nfixture"),
    mime = "application/pdf",
    origin = "https://storage.qa.invalid";
  const client = {
    storage: {
      from: () => ({
        createSignedUrl: async () => ({
          data: { signedUrl: origin + "/storage/v1/object/sign/qa" },
          error: null,
        }),
      }),
    },
  } as unknown as Parameters<typeof verifyUploadedFile>[0];
  const intent = () =>
    ({
      bucket: "learning-resources",
      object_path: "qa.pdf",
      spec: {
        size: content.length,
        mime,
        sha256: createHash("sha256").update(content).digest("hex"),
      },
    }) as UploadIntent;
  global.fetch = async () =>
    new Response(content, { headers: { "content-type": mime } });
  try {
    const valid = intent();
    await verifyUploadedFile(client, valid);
    content = Buffer.from("%PDF-1.4\nchanged");
    await assert.rejects(
      verifyUploadedFile(client, valid),
      InvalidUploadedFile,
    );
    content = Buffer.from("not a PDF");
    await assert.rejects(
      verifyUploadedFile(client, intent()),
      InvalidUploadedFile,
    );
    content = Buffer.from("%PDF-1.4");
    const wrongSize = intent();
    wrongSize.spec.size = 1;
    await assert.rejects(
      verifyUploadedFile(client, wrongSize),
      InvalidUploadedFile,
    );
    const wrongMime = intent();
    mime = "text/html";
    await assert.rejects(
      verifyUploadedFile(client, wrongMime),
      InvalidUploadedFile,
    );
    mime = "text/plain";
    content = Buffer.from([0xc3, 0x28]);
    await assert.rejects(
      verifyUploadedFile(client, intent()),
      InvalidUploadedFile,
    );
    content = Buffer.from("valid text");
    await verifyUploadedFile(client, intent());
    origin = "https://untrusted.invalid";
    await assert.rejects(
      verifyUploadedFile(client, intent()),
      /STORAGE_ORIGIN_INVALID/,
    );
  } finally {
    global.fetch = previousFetch;
    if (previousUrl === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = previousUrl;
  }
});
