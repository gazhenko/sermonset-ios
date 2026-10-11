// Isolated core integration server: no changes under server/, no package installation.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, generateKeyPairSync } from 'node:crypto';
import { spawn } from 'node:child_process';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const directory = resolve(root, 'build/core-server');
const wrangler = resolve(root, 'server/node_modules/.bin/wrangler');
const action = process.argv[2] || 'prepare';
if (action === 'prepare') {
  await mkdir(directory, {recursive: true});
  let config = await readFile(resolve(root, 'server/wrangler.toml'), 'utf8');
  config = config.replace(/^routes\s*=.*$/m, "").replace('main = "src/index.ts"', `main = "${root}/server/src/index.ts"`)
    .replace('migrations_dir = "migrations"', `migrations_dir = "${root}/server/migrations"`)
    .replace('directory = "../web"', `directory = "${root}/web"`)
    .replace(/PUBLIC_BASE_URL = "[^"]+"/, 'PUBLIC_BASE_URL = "http://127.0.0.1:8788"')
    .replace(/TOKEN_KEY_ID = "[^"]+"/, 'TOKEN_KEY_ID = "core-integration-v1"');
  await writeFile(resolve(directory, 'wrangler.toml'), config);
  const {privateKey, publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
  const bootstrap = randomBytes(48).toString('base64url');
  const env = {TOKEN_SIGNING_JWK: JSON.stringify(privateKey.export({format:'jwk'})),
    TOKEN_PUBLIC_KEYS: JSON.stringify([{kid:'core-integration-v1',alg:'ES256',publicKey: publicKey.export({format:'jwk'})}]),
    CAPABILITY_SECRET: randomBytes(48).toString('base64url'), ADMIN_BOOTSTRAP_SECRET: bootstrap};
  await writeFile(resolve(directory, '.dev.vars'), Object.entries(env).map(([k,v]) => `${k}='${v}'`).join('\n')+'\n', {mode:0o600});
  await writeFile(resolve(directory, 'bootstrap.txt'), bootstrap, {mode:0o600});
  console.log('Prepared isolated core server configuration and generated local-only test secrets in build/core-server.');
} else {
  const args = action === 'migrate' ? ['d1','migrations','apply','DB','--local'] : ['dev','--local','--ip','127.0.0.1','--port','8788'];
  args.push('--config', resolve(directory,'wrangler.toml'), '--persist-to', resolve(root,'build/wrangler-core'));
  const child = spawn(wrangler,args,{cwd:directory,stdio:'inherit',env:{...process.env,WRANGLER_SEND_METRICS:'false'}});
  for (const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>child.kill(signal));
  child.on('error', error => { console.error(error.message); process.exitCode = 1; });
  child.on('exit', code=>process.exit(code??1));
}
