// Isolated QA recovery only. Dry run by default; never deletes resource records.
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import net from "node:net";
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
if (url !== "http://127.0.0.1:58921")
  throw new Error("Dedicated QA API required.");
const client = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
async function ok(promise) {
  const { data, error } = await promise;
  assert(!error, error?.message);
  return data;
}
const apply = process.argv.includes("--apply");
if (apply) {
  const listening = await new Promise((resolve) => {
    const socket = net.connect(3008, "127.0.0.1");
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("error", () => resolve(false));
  });
  if (listening)
    throw new Error(
      "Stop the local Next preview before applying compensation, so it cannot race a retry. Dry run is safe while it runs.",
    );
}
const jobs = await ok(
  client
    .from("resource_upload_jobs")
    .select("*")
    .in("state", ["pending", "cleanup_required"])
    .lt("updated_at", new Date(Date.now() - 10 * 60 * 1000).toISOString()),
);
let completed = 0,
  cleaned = 0;
for (const job of jobs) {
  const row = await ok(
    client
      .from("learning_resources")
      .select("id,status,storage_path")
      .eq("id", job.id)
      .maybeSingle(),
  );
  if (row) {
    // Never remove an object referenced by any historical resource row.
    assert.equal(row.storage_path, job.storage_path);
    if (apply)
      await ok(
        client
          .from("resource_upload_jobs")
          .update({ state: "complete", updated_at: new Date().toISOString() })
          .eq("id", job.id),
      );
    completed++;
  } else {
    assert(
      job.storage_path.startsWith(
        `classes/${job.class_id}/resources/${job.id}/`,
      ),
    );
    if (apply) {
      await ok(
        client.storage.from("learning-resources").remove([job.storage_path]),
      );
      await ok(
        client
          .from("resource_upload_jobs")
          .update({ state: "cleaned", updated_at: new Date().toISOString() })
          .eq("id", job.id),
      );
    }
    cleaned++;
  }
}
console.log(
  JSON.stringify({
    mode: apply ? "applied" : "dry-run",
    committedUploads: completed,
    unreferencedFiles: cleaned,
    resourceRowsDeleted: 0,
  }),
);
