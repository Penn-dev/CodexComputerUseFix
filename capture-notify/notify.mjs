import { spawn } from 'node:child_process';
import path from 'node:path';
import { createCaptureHealth } from './health.mjs';

// The trusted worker uses an isolated Windows desktop. Its existing wrapper
// displays the popup on the user's desktop after receiving this stderr event.
export function notifyDesktop(message) {
  const tag = process.env.CODEX_CU_NOTIFY_TAG;
  if (!tag) return Promise.reject(new Error('CU desktop notification bridge is unavailable'));
  return new Promise((resolve, reject) => {
    process.stderr.write(`codex-cu-notify:${tag}:${JSON.stringify({message})}\n`, error => error ? reject(error) : resolve());
  });
}

export function showDesktopNotification(message) {
  return new Promise((resolve, reject) => {
    const target = process.env.USERNAME;
    if (!target) { reject(new Error('Windows notification user is unavailable')); return; }
    const child = spawn(path.join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'msg.exe'),
      [target, '/TIME:120', message], { windowsHide: true, stdio: 'ignore' });
    child.once('error', reject);
    child.once('exit', code => code === 0 ? resolve() : reject(new Error(`msg.exe exited with ${code}`)));
  });
}

export const observeCapture = createCaptureHealth({
  notify: notifyDesktop,
  report(message) { globalThis.nodeRepl?.write?.(message); },
});

export function decorateCaptureRpc(handleRpc, observe = observeCapture) {
  let nativeReleaseAvailable = false;
  return async function(request) {
    if (request.type === 'execute' && request.method === 'compat_status') {
      return { captureReminder: 'on-result', polling: false, nativeReleaseAvailable };
    }
    const capture = request.type === 'execute' && request.method === 'get_window_state' && request.args?.[0]?.include_screenshot !== false;
    let metadata = globalThis.nodeRepl?.requestMeta ?? {};
    if (typeof metadata === 'string') { try { metadata = JSON.parse(metadata); } catch { metadata = {}; } }
    let nested = metadata['x-codex-turn-metadata'] ?? {};
    if (typeof nested === 'string') { try { nested = JSON.parse(nested); } catch { nested = {}; } }
    metadata = { ...metadata, ...nested };
    try {
      const result = await handleRpc(request);
      if (request.type === 'setup' && result?.target === 'windows') {
        nativeReleaseAvailable = result.methods.includes('end_turn');
        return { ...result, methods: [...result.methods, 'compat_status'] };
      }
      if (capture && result?.screenshots?.length) await observe(metadata);
      return result;
    } catch (error) {
      if (capture) await observe(metadata, error);
      throw error;
    }
  };
}
