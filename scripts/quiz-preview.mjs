// Isolated owner preview. No linked/hosted Supabase operation is supported.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, spawnSync } from "node:child_process";
import { parseEnv } from "node:util";
import { randomBytes } from "node:crypto";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspace = path.join(root, ".tmp", "quiz-preview");
const command = process.argv[2] ?? "start";
const project = "BQQuizQA20261112";
function cliPath() {
  if (process.env.BQ_SUPABASE_CLI) return process.env.BQ_SUPABASE_CLI;
  if (process.platform === "win32") {
    const cache = path.join(process.env.LOCALAPPDATA, "npm-cache", "_npx");
    for (const entry of fs.readdirSync(cache)) {
      const candidate = path.join(
        cache,
        entry,
        "node_modules",
        "@supabase",
        "cli-windows-x64",
        "bin",
        "supabase.exe",
      );
      if (fs.existsSync(candidate)) return candidate;
    }
  }
  return "supabase";
}
function cli(args) {
  const result = spawnSync(cliPath(), ["--workdir", workspace, ...args], {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 10_000_000,
  });
  if (result.status !== 0) {
    fs.mkdirSync(workspace, { recursive: true });
    fs.writeFileSync(
      path.join(workspace, "cli-error.log"),
      result.stderr ?? result.error?.message ?? "CLI failed",
    );
    throw new Error(
      "Isolated CLI command failed. Check .tmp/quiz-preview/cli-error.log.",
    );
  }
  return result.stdout;
}
function verifyConfig() {
  const config = fs.readFileSync(
    path.join(workspace, "supabase", "config.toml"),
    "utf8",
  );
  if (
    !config.includes(`project_id = "${project}"`) ||
    !config.includes("port = 58921")
  )
    throw new Error("Dedicated quiz QA configuration required.");
}
if (command === "setup" || command === "setup-recovery") {
  fs.mkdirSync(path.join(workspace, "supabase", "migrations"), {
    recursive: true,
  });
  const configPath = path.join(workspace, "supabase", "config.toml");
  if (fs.existsSync(configPath)) verifyConfig();
  const config = fs
    .readFileSync(path.join(root, "supabase", "config.toml"), "utf8")
    .replace('project_id = "ByteQuest"', `project_id = "${project}"`)
    .replaceAll("573", "589")
    .replaceAll("http://127.0.0.1:3000", "http://127.0.0.1:3008");
  fs.writeFileSync(configPath, config);
  fs.mkdirSync(path.join(workspace, "supabase", "templates"), {recursive:true});
  fs.copyFileSync(path.join(root,"supabase","templates","recovery.html"),path.join(workspace,"supabase","templates","recovery.html"));
  for (const file of fs.readdirSync(
    path.join(root, "supabase", "migrations"),
  )) {
    if (file.endsWith(".sql"))
      fs.copyFileSync(
        path.join(root, "supabase", "migrations", file),
        path.join(workspace, "supabase", "migrations", file),
      );
  }
  fs.copyFileSync(
    path.join(root, "supabase", "seed.sql"),
    path.join(workspace, "supabase", "seed.sql"),
  );
  const storage = spawnSync(
    "docker",
    [
      "inspect",
      "--format",
      "{{.State.Running}}",
      `supabase_storage_${project}`,
    ],
    { encoding: "utf8" },
  );
  const database = spawnSync(
    "docker",
    ["inspect", "--format", "{{.State.Running}}", `supabase_db_${project}`],
    { encoding: "utf8" },
  );
  // `start` leaves an already-running partial stack untouched. Stop preserves
  // its named data volumes; never use --no-backup or a database reset.
  if (command === "setup-recovery" || (database.stdout.trim() === "true" && storage.stdout.trim() !== "true"))
    cli(["stop"]);
  cli([
    "start",
    "-x",
    "realtime,imgproxy,postgres-meta,studio,edge-runtime,logflare,vector,supavisor",
  ]);
  console.log(
    "Dedicated quiz QA stack ready at http://127.0.0.1:58921. No original stack or hosted project changed.",
  );
} else if (command === "migrate-resources") {
  verifyConfig();
  const container = `supabase_db_${project}`;
  const file = "20261112151434_resource_quiz_sources_and_request_safety.sql";
  const sql = fs.readFileSync(
    path.join(root, "supabase", "migrations", file),
    "utf8",
  );
  const body = sql.replace(/^begin;\s*$/m, "").replace(/^commit;\s*$/m, "");
  const query = (input) =>
    spawnSync(
      "docker",
      [
        "exec",
        "-i",
        container,
        "psql",
        "-U",
        "postgres",
        "-d",
        "postgres",
        "-v",
        "ON_ERROR_STOP=1",
        "-Atq",
      ],
      { input, encoding: "utf8" },
    );
  const exists = query(
    "select count(*) from supabase_migrations.schema_migrations where version='20261112151434';",
  );
  if (exists.status !== 0)
    throw new Error("Dedicated QA migration history unavailable.");
  if (exists.stdout.trim() === "1") {
    console.log("Targeted QA resource migration already applied.");
    process.exit(0);
  }
  const hashes = `select md5(coalesce(string_agg(row_to_json(t)::text, '|' order by id),'')) from public.`;
  const protectedTables = [
    "quiz_attempts",
    "quiz_results",
    "quiz_answers",
    "quiz_versions",
    "quizzes",
    "quiz_items",
    "learning_resources",
    "profiles",
  ];
  const before = protectedTables
    .map((table) => `create temp table before_${table} as ${hashes}${table} t;`)
    .join("\n");
  const after = protectedTables
    .map(
      (table) =>
        `if (${hashes}${table} t)<>(select * from before_${table}) then raise exception 'QA_DATA_CHANGED_${table}'; end if;`,
    )
    .join("\n");
  const result = query(
    `begin;\n${before}\n${body}\ndo $$ begin ${after} end $$;\ninsert into supabase_migrations.schema_migrations(version,name,statements) values ('20261112151434','resource_quiz_sources_and_request_safety',array[$migration$${sql}$migration$]);\ncommit;`,
  );
  if (result.status !== 0) {
    console.error(result.stderr);
    throw new Error("Targeted QA migration failed and rolled back.");
  }
  console.log(
    "Targeted resource migration applied only to dedicated QA; protected row hashes unchanged.",
  );
} else {
  verifyConfig();
  const config = JSON.parse(cli(["status", "-o", "json"]));
  if (config.API_URL !== "http://127.0.0.1:58921")
    throw new Error("Dedicated quiz QA API required.");
  const env = {
    ...process.env,
    NEXT_PUBLIC_SUPABASE_URL: config.API_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
      config.PUBLISHABLE_KEY ?? config.ANON_KEY,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: config.ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY: config.SERVICE_ROLE_KEY,
    OPENROUTER_API_KEY: "",
    OPENROUTER_REASONING_EFFORT: "low",
  };
  delete env.BQ_AI_TEST_ENDPOINT;
  const cronFile=path.join(workspace,'cleanup-secret');
  if(!fs.existsSync(cronFile))fs.writeFileSync(cronFile,randomBytes(32).toString('hex'),{flag:'wx'});
  env.CRON_SECRET=fs.readFileSync(cronFile,'utf8');
  env.BQ_ISOLATED_QA = project;
  if (command === "test-start")
    env.BQ_AI_TEST_ENDPOINT = "http://127.0.0.1:3007/chat/completions";
  if (["ai-start", "ai-test"].includes(command)) {
    const keyFile = path.join(root, ".tmp", "quiz-ai.env");
    if (!fs.existsSync(keyFile)) {
      console.log(
        "BLOCKED: local AI key missing. Add OPENROUTER_API_KEY to ignored .tmp/quiz-ai.env; never paste it into chat. No provider request was made.",
      );
      process.exit(2);
    }
    const values = parseEnv(fs.readFileSync(keyFile, "utf8"));
    if (!values.OPENROUTER_API_KEY?.trim())
      throw new Error("The local AI key is missing.");
    const model = values.OPENROUTER_MODEL ?? "openrouter/free";
    if (model !== "openrouter/free" && !model.endsWith(":free"))
      throw new Error("This local testing launcher permits only free models.");
    env.OPENROUTER_API_KEY = values.OPENROUTER_API_KEY;
    env.OPENROUTER_MODEL = model;
    if (values.OPENROUTER_REASONING_EFFORT !== undefined) {
      if (!["low", "none"].includes(values.OPENROUTER_REASONING_EFFORT))
        throw new Error("Local reasoning effort must be low or none.");
      env.OPENROUTER_REASONING_EFFORT = values.OPENROUTER_REASONING_EFFORT;
    }
  }
  let cwd = root;
  let executable = process.execPath;
  let args;
  if (command === "seed") {
    env.BQ_QUIZ_QA_ACCOUNT_FILE = path.join(
      root,
      ".tmp",
      "quiz-preview-accounts.json",
    );
    args = ["scripts/quiz-workflow-api-tests.mjs"];
  } else if (["resource-tests", "enrollment-tests", "release-gates"].includes(command)) {
    if (!env.BQ_PLAYWRIGHT_MODULE && process.platform === "win32") {
      const cache = path.join(process.env.LOCALAPPDATA, "npm-cache", "_npx");
      for (const entry of fs.readdirSync(cache)) {
        const candidate = path.join(
          cache,
          entry,
          "node_modules",
          "playwright",
          "index.mjs",
        );
        if (fs.existsSync(candidate)) {
          env.BQ_PLAYWRIGHT_MODULE = candidate;
          break;
        }
      }
    }
    args = [command === 'release-gates' ? 'scripts/release-gates-qa.mjs' : command === "enrollment-tests" ? "scripts/learner-enrollment-tests.mjs" : "scripts/resource-ai-workflow-tests.mjs", ...process.argv.slice(3)];
  } else if (command === "owner-resources") {
    args = ["scripts/quiz-resource-owner-setup.mjs"];
  } else if (["activity-tests", "activity-owner-setup", "activity-browser-tests"].includes(command)) {
    args = [command === "activity-tests" ? "scripts/activity-api-tests.mjs" : command === "activity-owner-setup" ? "scripts/activity-owner-setup.mjs" : "scripts/activity-browser-tests.mjs", ...process.argv.slice(3)];
  } else if (command === "end-qa-sessions") {
    args = ["scripts/quiz-qa-end-sessions.mjs"];
  } else if (command === "ai-test") {
    args = ["scripts/quiz-ai-live-synthetic-test.mjs"];
  } else if (command === "notification-tests") {
    args = ["scripts/notification-api-tests.mjs", ...process.argv.slice(3)];
  } else if (command === "notification-browser-tests") {
    args = ["scripts/notification-browser-tests.mjs", ...process.argv.slice(3)];
  } else if (command === "notification-owner-setup") {
    args = ["scripts/notification-owner-setup.mjs"];
  } else if (command === "quiz-regression") {
    args = ["scripts/quiz-workflow-api-tests.mjs"];
  } else if (command === "reconcile-uploads") {
    args = ["scripts/resource-upload-reconcile.mjs", ...process.argv.slice(3)];
  } else if (command === "learner") {
    env.FLUTTER_WINDOWS = "false";
    const definePath = path.join(root, ".tmp", "quiz-local-web-defines.json");
    // Only public client configuration is written to the Flutter define file.
    fs.writeFileSync(
      definePath,
      JSON.stringify({
        BQ_SUPABASE_URL: config.API_URL,
        BQ_SUPABASE_ANON_KEY: config.PUBLISHABLE_KEY ?? config.ANON_KEY,
        BQ_PRACTICE_API_URL: "http://127.0.0.1:3008/api/learner/practice",
      }),
    );
    cwd = path.join(root, "ByteQuest-Mobile-App");
    executable = process.platform === "win32" ? "cmd.exe" : "flutter";
    args = [
      ...(process.platform === "win32" ? ["/d", "/c", "flutter"] : []),
      "run",
      "--no-pub",
      "--no-web-resources-cdn",
      "-d",
      "web-server",
      "--web-hostname",
      "127.0.0.1",
      "--web-port",
      "3009",
      `--dart-define-from-file=${definePath}`,
    ];
    // Flutter needs no server credentials.
    delete env.SUPABASE_SERVICE_ROLE_KEY;
  } else if (
    ["start", "build", "dev", "ai-start", "test-start"].includes(command)
  ) {
    cwd = path.join(root, "ByteQuest-Web-Dashboard");
    args = [
      path.join(cwd, "node_modules", "next", "dist", "bin", "next"),
      ["ai-start", "test-start"].includes(command) ? "start" : command,
      ...(command === "build"
        ? []
        : ["--hostname", "127.0.0.1", "--port", "3008"]),
    ];
  } else
    throw new Error(
      "Use setup, seed, build, start, ai-start, test-start, dev or learner.",
    );
  const child = spawn(executable, args, { cwd, env, stdio: "inherit" });
  child.on("error", (error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
  child.on("exit", (code) => {
    process.exitCode = code ?? 1;
  });
}
