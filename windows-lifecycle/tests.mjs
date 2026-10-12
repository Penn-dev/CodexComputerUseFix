import assert from 'node:assert/strict';
import test from 'node:test';
import { attachWindowsLifecycle } from './lifecycle.mjs';

function fixture() {
  const calls = [];
  const client = {};
  let handler;
  let removed = 0;
  let failCleanup = false;
  const transport = attachWindowsLifecycle(client, {
    async request(method, params, options) {
      calls.push({ method, params, options });
      if (method === 'get_window_state') throw new Error('FrameArrived timed out');
      if (method === 'end_turn' && failCleanup) throw new Error('cleanup failed');
      return {};
    },
    async close() { calls.push({ method: 'close' }); },
  }, {
    addTurnEndedHandler(value) { handler = value; return () => { removed++; }; },
  });
  return { client, transport, calls, run: event => handler.run(event), removed: () => removed, fail: value => { failCleanup = value; } };
}
const metadata = { session_id: 'session-a', turn_id: 'turn-a' };
const options = { codexTurnMetadata: metadata };

test('public RPC discovers cleanup; unused and repeated cleanup do not start capture', async () => {
  const f = fixture();
  assert.ok(Object.keys(f.client).includes('end_turn'));
  await f.client.end_turn();
  assert.equal(f.calls.length, 0);
  await f.transport.request('list_windows', {}, options);
  await f.client.end_turn();
  await f.client.end_turn();
  assert.deepEqual(f.calls.map(c => c.method), ['list_windows', 'end_turn', 'close']);
  assert.equal(f.removed(),1);
  assert.deepEqual(f.calls.find(c => c.method==='end_turn').options.codexTurnMetadata, metadata);
  await assert.rejects(f.transport.request('click', {}, options), /released/);
});

test('failed capture remains eligible for cleanup; unrelated turn cannot release it', async () => {
  const f = fixture();
  await assert.rejects(f.transport.request('get_window_state', {}, options), /timed out/);
  await f.run({ session_id: 'other', turn_id: 'turn-a' });
  assert.equal(f.calls.length, 1);
  await f.run(metadata);
  await f.run(metadata);
  assert.deepEqual(f.calls.map(c => c.method), ['get_window_state', 'end_turn', 'close']);
  await assert.rejects(f.transport.request('list_windows', {}, { codexTurnMetadata: { ...metadata, turn_id: 'turn-b' } }), /released/);
  await f.run(metadata);
  assert.equal(f.calls.at(-1).method, 'close');
});

test('cleanup failure remains visible and retryable', async () => {
  const f = fixture();
  await f.transport.request('list_windows', {}, options);
  f.fail(true);
  await assert.rejects(f.client.end_turn(), /cleanup failed/);
  f.fail(false);
  await f.client.end_turn();
  assert.equal(f.calls.filter(c => c.method === 'end_turn').length, 2);
});

test('physical Escape closes this connection without restarting the stopped helper', async () => {
  const calls=[];
  const client={};
  const transport=attachWindowsLifecycle(client, {
    async request(method){calls.push(method);throw Error('Computer Use was stopped by the user with the physical Escape key. Stop your work.');},
    async close(){calls.push('close');},
  },{});
  await assert.rejects(transport.request('get_window_state',{},options),/physical Escape/);
  await client.end_turn();
  assert.deepEqual(calls,['get_window_state','close']);
});
