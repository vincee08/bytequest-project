// Isolated owner preview. No linked/hosted Supabase operation is supported.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn, spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const workspace = path.join(root, '.tmp', 'quiz-preview');
const command = process.argv[2] ?? 'start';
const project = 'BQQuizQA20261112';
function cliPath() {
  if (process.env.BQ_SUPABASE_CLI) return process.env.BQ_SUPABASE_CLI;
  if (process.platform === 'win32') {
    const cache = path.join(process.env.LOCALAPPDATA, 'npm-cache', '_npx');
    for (const entry of fs.readdirSync(cache)) {
      const candidate = path.join(cache, entry, 'node_modules', '@supabase', 'cli-windows-x64', 'bin', 'supabase.exe');
      if (fs.existsSync(candidate)) return candidate;
    }
  }
  return 'supabase';
}
function cli(args) {
  const result = spawnSync(cliPath(), ['--workdir', workspace, ...args], { cwd: root, encoding: 'utf8', maxBuffer: 10_000_000 });
  if (result.status !== 0) {
    fs.mkdirSync(workspace, { recursive: true });
    fs.writeFileSync(path.join(workspace, 'cli-error.log'), result.stderr ?? result.error?.message ?? 'CLI failed');
    throw new Error('Isolated CLI command failed. Check .tmp/quiz-preview/cli-error.log.');
  }
  return result.stdout;
}
function verifyConfig() {
  const config = fs.readFileSync(path.join(workspace, 'supabase', 'config.toml'), 'utf8');
  if (!config.includes(`project_id = "${project}"`) || !config.includes('port = 58921')) throw new Error('Dedicated quiz QA configuration required.');
}
if (command === 'setup') {
  fs.mkdirSync(path.join(workspace, 'supabase', 'migrations'), { recursive: true });
  const configPath = path.join(workspace, 'supabase', 'config.toml');
  if (fs.existsSync(configPath)) verifyConfig();
  const config = fs.readFileSync(path.join(root, 'supabase', 'config.toml'), 'utf8')
    .replace('project_id = "ByteQuest"', `project_id = "${project}"`).replaceAll('573', '589').replaceAll('http://127.0.0.1:3000', 'http://127.0.0.1:3008');
  fs.writeFileSync(configPath, config);
  for (const file of fs.readdirSync(path.join(root, 'supabase', 'migrations'))) {
    if (file.endsWith('.sql')) fs.copyFileSync(path.join(root, 'supabase', 'migrations', file), path.join(workspace, 'supabase', 'migrations', file));
  }
  fs.copyFileSync(path.join(root, 'supabase', 'seed.sql'), path.join(workspace, 'supabase', 'seed.sql'));
  cli(['start', '-x', 'realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor']);
  console.log('Dedicated quiz QA stack ready at http://127.0.0.1:58921. No original stack or hosted project changed.');
} else {
  verifyConfig();
  const config = JSON.parse(cli(['status', '-o', 'json']));
  if (config.API_URL !== 'http://127.0.0.1:58921') throw new Error('Dedicated quiz QA API required.');
  const env = { ...process.env, NEXT_PUBLIC_SUPABASE_URL: config.API_URL, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: config.PUBLISHABLE_KEY ?? config.ANON_KEY, NEXT_PUBLIC_SUPABASE_ANON_KEY: config.ANON_KEY, SUPABASE_SERVICE_ROLE_KEY: config.SERVICE_ROLE_KEY, OPENROUTER_API_KEY: '' };
  let cwd = root;
  let executable = process.execPath;
  let args;
  if (command === 'seed') {
    env.BQ_QUIZ_QA_ACCOUNT_FILE = path.join(root, '.tmp', 'quiz-preview-accounts.json');
    args = ['scripts/quiz-workflow-api-tests.mjs'];
  } else if (command === 'learner') {
    const definePath = path.join(root, '.tmp', 'quiz-local-web-defines.json');
    // Only public client configuration is written to the Flutter define file.
    fs.writeFileSync(definePath, JSON.stringify({ BQ_SUPABASE_URL: config.API_URL, BQ_SUPABASE_ANON_KEY: config.PUBLISHABLE_KEY ?? config.ANON_KEY, BQ_PRACTICE_API_URL: 'http://127.0.0.1:3008' }));
    cwd = path.join(root, 'ByteQuest-Mobile-App');
    executable = process.platform === 'win32' ? 'cmd.exe' : 'flutter';
    args = [...(process.platform === 'win32' ? ['/d', '/c', 'flutter'] : []), 'run', '--no-pub', '-d', 'web-server', '--web-hostname', '127.0.0.1', '--web-port', '3009', `--dart-define-from-file=${definePath}`];
    // Flutter needs no server credentials.
    delete env.SUPABASE_SERVICE_ROLE_KEY;
  } else if (['start', 'build', 'dev'].includes(command)) {
    cwd = path.join(root, 'ByteQuest-Web-Dashboard');
    args = [path.join(cwd, 'node_modules', 'next', 'dist', 'bin', 'next'), command, ...(command === 'build' ? [] : ['--hostname', '127.0.0.1', '--port', '3008'])];
  } else throw new Error('Use setup, seed, build, start, dev or learner.');
  const child = spawn(executable, args, { cwd, env, stdio: 'inherit' });
  child.on('error', error => { console.error(error.message); process.exitCode = 1; });
  child.on('exit', code => { process.exitCode = code ?? 1; });
}
