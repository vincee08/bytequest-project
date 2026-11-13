export function duplicateStorageUpload(status: number, body: string) {
  if (status === 409) return true;
  if (status !== 400) return false;
  try {
    const error = JSON.parse(body);
    return (
      String(error.statusCode) === "409" &&
      (error.code === "KeyAlreadyExists" || error.error === "Duplicate")
    );
  } catch {
    return false;
  }
}

/** Browser bytes go only to a server-authorized, exact Storage path. */
export async function directUpload(
  file: File,
  metadata: {
    purpose: "resource" | "homework";
    target_id: string;
    title?: string;
    description?: string;
  },
  onProgress: (percent: number) => void,
) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    await file.arrayBuffer(),
  );
  const sha256 = Array.from(new Uint8Array(digest), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  const request = async (body: object) => {
    const response = await fetch("/api/uploads", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(150_000),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok)
      throw new Error(
        data.error ??
          "Upload could not be confirmed. Retry the same file and details.",
      );
    return data;
  };
  const prepared = await request({
    action: "prepare",
    ...metadata,
    filename: file.name,
    mime: file.type,
    size: file.size,
    sha256,
  });
  if (prepared.complete) {
    onProgress(100);
    return prepared.record;
  }
  if (!prepared.uploaded) {
    const storage = new URL(prepared.signed_url);
    if (
      storage.origin !==
        new URL(process.env.NEXT_PUBLIC_SUPABASE_URL!).origin ||
      !storage.pathname.startsWith("/storage/v1/object/upload/sign/")
    )
      throw new Error("The upload endpoint is invalid.");
    await new Promise<void>((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      xhr.open("PUT", storage.toString());
      xhr.timeout = 180_000;
      xhr.setRequestHeader("Content-Type", file.type);
      xhr.setRequestHeader("x-upsert", "false");
      xhr.upload.onprogress = (event) => {
        if (event.lengthComputable)
          onProgress(
            Math.min(95, Math.round((event.loaded / event.total) * 95)),
          );
      };
      xhr.onload = () => {
        if (
          (xhr.status >= 200 && xhr.status < 300) ||
          duplicateStorageUpload(xhr.status, xhr.responseText)
        )
          resolve();
        else
          reject(
            new Error(
              "Storage could not receive the file. Retry the same file and details.",
            ),
          );
      };
      xhr.onerror = xhr.ontimeout = () =>
        reject(
          new Error(
            "The upload connection was interrupted. Retry the same file and details.",
          ),
        );
      xhr.send(file);
    });
  }
  onProgress(95);
  const completed = await request({
    action: "complete",
    upload_id: prepared.upload_id,
  });
  onProgress(100);
  return completed.record;
}
