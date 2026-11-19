// The learner app's version marker (final fix wave, client version
// interface). The 1.2.0+ app sends x-bytequest-app-version: <kAppVersion> on
// every Supabase and dashboard API request; the server refuses simulation-
// assessment attempt starts and essay-quiz starts from clients that do not
// identify as at least app_release_config.min_supported_app_version.
// Scripts that act as the learner app send the same header, with the version
// read from the app source so the two cannot drift apart.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SOURCE = path.join(ROOT, "ByteQuest-Mobile-App", "lib", "services", "app_version_service.dart");

export const APP_VERSION_HEADER = "x-bytequest-app-version";

export function appVersion() {
  const match = fs.readFileSync(SOURCE, "utf8").match(/const String kAppVersion = '(\d+\.\d+\.\d+)';/);
  if (!match) throw new Error(`kAppVersion not found in ${path.relative(ROOT, SOURCE)}`);
  return match[1];
}

/** Headers a learner-app client sends (Supabase global headers, dashboard API calls). */
export function appClientHeaders() {
  return { [APP_VERSION_HEADER]: appVersion() };
}
