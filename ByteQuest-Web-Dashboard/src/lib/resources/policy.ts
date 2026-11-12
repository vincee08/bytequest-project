export const LEARNING_RESOURCE_BUCKET = "learning-resources";
export const MAX_LEARNING_RESOURCE_BYTES = 50 * 1024 * 1024;

export const ALLOWED_LEARNING_RESOURCE_TYPES = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "video/mp4": "mp4",
  "video/webm": "webm",
} as const;

export type AllowedLearningResourceMime =
  keyof typeof ALLOWED_LEARNING_RESOURCE_TYPES;

export function isAllowedLearningResourceMime(
  value: string,
): value is AllowedLearningResourceMime {
  return Object.hasOwn(ALLOWED_LEARNING_RESOURCE_TYPES, value);
}

/** Signatures supplement the allowlist; they do not assert a document is readable. */
export function matchesResourceContent(
  mime: AllowedLearningResourceMime,
  bytes: Uint8Array,
) {
  const starts = (...signature: number[]) =>
    signature.every((value, index) => bytes[index] === value);
  const ascii = (start: number, end: number) =>
    String.fromCharCode(...bytes.slice(start, end));
  switch (mime) {
    case "application/pdf":
      return ascii(0, 5) === "%PDF-";
    case "image/jpeg":
      return starts(0xff, 0xd8, 0xff);
    case "image/png":
      return starts(137, 80, 78, 71, 13, 10, 26, 10);
    case "image/webp":
      return ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP";
    case "video/mp4":
      return ascii(4, 8) === "ftyp";
    case "video/webm":
      return starts(0x1a, 0x45, 0xdf, 0xa3);
  }
}
