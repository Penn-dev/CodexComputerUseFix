import { registerHooks } from 'node:module';
import { fileURLToPath } from 'node:url';

const lifecycleUrl = new URL('../windows-lifecycle/lifecycle.mjs', import.meta.url).href;
const notificationUrl = new URL('../capture-notify/notify.mjs', import.meta.url).href;
const baseNeedle = 'i(this,c,o.transport,"f")';
const serviceNeedle = 'if(null==o){';

export function transformNativeModule(url, source) {
  const filename = fileURLToPath(url).replaceAll('\\', '/');
  if (!/\/@oai\/(?:sky|cua)\/dist\/project\/cua\/sky_js\/src\//.test(filename)) return source;
  if (filename.endsWith('/targets/windows/internal/computer_use_client_base.js')) {
    if (source.includes('codexCompatAttach')) {
      const legacyImport = 'import{attachWindowsLifecycle as codexCompatAttach}from"./codex_windows_lifecycle.mjs";';
      if (!source.startsWith(legacyImport) || source.split('i(this,c,codexCompatAttach(this,o.transport),"f")').length !== 2) {
        return source;
      }
      return source.replace(legacyImport, `import{attachWindowsLifecycle as codexCompatAttach}from${JSON.stringify(lifecycleUrl)};`);
    }
    if (source.split(baseNeedle).length !== 2) return source;
    return `import{attachWindowsLifecycle as codexCompatAttach}from${JSON.stringify(lifecycleUrl)};` +
      source.replace(baseNeedle, 'i(this,c,codexCompatAttach(this,o.transport),"f")');
  }
  if (filename.endsWith('/src/service.js')) {
    const exported = source.match(/export\{([A-Za-z_$][\w$]*) as handleRpc\};/);
    if (!exported) return source;
    const lifecycle = source.split(serviceNeedle).length === 2 && source.includes('const e=n();o=r(e)');
    let updated = lifecycle ? source.replace(serviceNeedle, 'codexCheckScope(s);if(null==o||codexReleased(o)){') : source;
    return `import{decorateCaptureRpc as codexCaptureRpc}from${JSON.stringify(notificationUrl)};` +
      (lifecycle ? `import{isReleased as codexReleased,checkServiceScope as codexCheckScope}from${JSON.stringify(lifecycleUrl)};` : '') +
      updated.replace(exported[0], `const codexObservedRpc=codexCaptureRpc(${exported[1]});export{codexObservedRpc as handleRpc};`);
  }
  return source;
}

registerHooks({
  load(url, context, nextLoad) {
    const result = nextLoad(url, context);
    if (!url.startsWith('file:') || result.format !== 'module' || result.source == null) return result;
    return { ...result, source: transformNativeModule(url, typeof result.source === 'string' ? result.source : Buffer.from(result.source).toString('utf8')) };
  },
});
