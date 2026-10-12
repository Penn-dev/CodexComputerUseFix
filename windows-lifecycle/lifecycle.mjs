const released = new WeakSet();
const endedBySession = new Map();
export const isReleased = client => released.has(client);

function requestMetadata(nodeRepl = globalThis.nodeRepl) {
  let metadata = nodeRepl?.requestMeta ?? {};
  if (typeof metadata === 'string') { try { metadata = JSON.parse(metadata); } catch { return {}; } }
  let nested = metadata['x-codex-turn-metadata'] ?? {};
  if (typeof nested === 'string') { try { nested = JSON.parse(nested); } catch { nested = {}; } }
  return { ...metadata, ...nested };
}
export function checkServiceScope(request) {
  if (request.type !== 'execute' || request.method === 'end_turn') return;
  const metadata = requestMetadata();
  if (metadata.turn_id && endedBySession.get(metadata.session_id) === metadata.turn_id) {
    throw new Error('Computer Use scope has been released; wait for a new turn before reconnecting');
  }
}

// Use normal turn cleanup and disconnect only this client's native pipe.
export function attachWindowsLifecycle(client, transport, nodeRepl = globalThis.nodeRepl) {
  let activeMetadata;
  let endedScope;
  let ending;
  let removeHandler;
  let stoppedByUser = false;

  const scopeOf = (metadata) =>
    typeof metadata?.session_id === 'string' && typeof metadata?.turn_id === 'string'
      ? JSON.stringify([metadata.session_id, metadata.turn_id])
      : undefined;

  async function endTurn() {
    if (ending) return ending;
    if (!activeMetadata) return;
    const metadata = activeMetadata;
    ending = (async () => {
      if (!stoppedByUser) await transport.request('end_turn', {}, { codexTurnMetadata: metadata });
      await transport.close();
    })();
    try {
      await ending;
      endedScope = scopeOf(metadata);
      if (metadata.session_id && metadata.turn_id) endedBySession.set(metadata.session_id, metadata.turn_id);
      released.add(client);
      if (activeMetadata === metadata) activeMetadata = undefined;
      removeHandler?.();
      removeHandler = undefined;
    } finally {
      ending = undefined;
    }
  }

  Object.defineProperty(client, 'end_turn', {
    enumerable: true,
    configurable: false,
    writable: false,
    value: endTurn,
  });

  if (typeof nodeRepl?.addTurnEndedHandler === 'function') {
    removeHandler = nodeRepl.addTurnEndedHandler({
      timeoutMs: 10000,
      async run(event) {
        const scope = scopeOf(event);
        if (scope && scope === scopeOf(activeMetadata)) await endTurn();
      },
    });
  }

  return {
    async request(method, params, options = {}) {
      if (ending) await ending;
      const metadata = options.codexTurnMetadata;
      const scope = scopeOf(metadata);
      if (method === 'end_turn') return endTurn();
      if (released.has(client) || (scope && scope === endedScope)) {
        throw new Error('Computer Use scope has been released; wait for a new turn before reconnecting');
      }
      // A failed capture can still leave an active helper scope.
      activeMetadata = metadata ?? {};
      try {
        return await transport.request(method, params, options);
      } catch (error) {
        if (String(error?.message ?? error).includes('Computer Use was stopped by the user with the physical Escape key.')) {
          stoppedByUser = true;
          await endTurn();
        }
        throw error;
      }
    },
    async close() {
      try {
        await endTurn();
      } finally {
        removeHandler?.();
        await transport.close();
      }
    },
  };
}
