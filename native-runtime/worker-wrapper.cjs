const { spawn } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { StringDecoder } = require('node:string_decoder');

const [cwd, command, ...args] = process.argv.slice(2);
if (!cwd || !command) throw new Error('Expected the official worker directory and command');
const worker = args.find(value => /[/\\]trusted-worker\.js$/.test(value));
const services = JSON.parse(process.env.NODE_REPL_TRUSTED_SERVICES ?? '{}');
if (worker && services.sky) {
  const nodeIndex = args.findIndex(value => path.basename(value).toLowerCase() === 'node.exe');
  if (nodeIndex < 0) throw new Error('The official trusted worker command has no Node executable');
  args.splice(nodeIndex + 1, 0, '--import', pathToFileURL(path.join(__dirname, 'bootstrap.mjs')).href);
}
const tag = worker && services.sky ? randomUUID() : undefined;
const env = tag ? { ...process.env, CODEX_CU_NOTIFY_TAG: tag } : process.env;
// Preserve the sandbox command and every protocol byte. The existing parent
// reads only its tagged notification events from stderr, forwarding stderr too.
const child = spawn(command, args, { cwd, env, stdio: ['inherit','inherit',tag ? 'pipe' : 'inherit'], windowsHide: true });
if (tag) {
  const decoder = new StringDecoder('utf8');
  const prefix = `codex-cu-notify:${tag}:`;
  let pending = '';
  child.stderr.on('data', chunk => {
    process.stderr.write(chunk);
    pending += decoder.write(chunk);
    let newline;
    while ((newline = pending.indexOf('\n')) >= 0) {
      const line = pending.slice(0,newline).replace(/\r$/, '');
      pending = pending.slice(newline+1);
      if (!line.startsWith(prefix)) continue;
      try {
        const { message } = JSON.parse(line.slice(prefix.length));
        if (typeof message !== 'string' || message.length > 2048) continue;
        import(pathToFileURL(path.join(__dirname,'../capture-notify/notify.mjs')).href)
          .then(({showDesktopNotification}) => showDesktopNotification(message))
          .catch(error => console.error(`CU desktop reminder failed: ${error.message}`));
      } catch { /* Preserve malformed diagnostics without displaying them. */ }
    }
    if (pending.length > 8192) pending = '';
  });
}
child.once('error', error => { console.error(error.message); process.exitCode = 1; });
child.once('exit', code => { process.exitCode = code ?? 1; });
