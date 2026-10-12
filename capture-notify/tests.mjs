import assert from 'node:assert/strict';
import test from 'node:test';
import { createCaptureHealth } from './health.mjs';
import { decorateCaptureRpc } from './notify.mjs';
const failure = new Error('FrameArrived timed out: timed out waiting on channel');
test('only repeated known capture failures notify; recovery and unrelated failures reset', async () => {
  let time=0; const notifications=[];
  const observe=createCaptureHealth({now:()=>time,notify:async message=>notifications.push(message)});
  const a={session_id:'a'},b={session_id:'b'};
  await observe(a,failure); await observe(b,failure); assert.equal(notifications.length,0);
  time+=1; await observe(a,failure); await observe(a,failure); assert.equal(notifications.length,1);
  await observe(a); await observe(a,failure); assert.equal(notifications.length,1);
  await observe(a,new Error('network failed')); await observe(a,failure); assert.equal(notifications.length,1);
  time+=600001; await observe(a,failure); assert.equal(notifications.length,1);
  await observe(a,failure); assert.equal(notifications.length,2);
  await observe({},failure); await observe({},failure); assert.equal(notifications.length,2);
});
test('delivery failure is reported and remains retryable without replacing capture errors', async () => {
  let attempts=0; const reports=[];
  const observe=createCaptureHealth({notify:async()=>{if(++attempts===1)throw Error('not delivered')},report:message=>reports.push(message)});
  await observe({session_id:'delivery'},failure); await observe({session_id:'delivery'},failure);
  assert.match(reports[0],/not delivered/); await observe({session_id:'delivery'},failure); assert.equal(attempts,2);
});
test('RPC observes actual capture results and preserves errors and unrelated calls', async () => {
  const previous = globalThis.nodeRepl;
  const observations = [];
  let result = { target: 'windows', methods: ['get_window_state', 'end_turn'] };
  let error;
  globalThis.nodeRepl = { requestMeta: { 'x-codex-turn-metadata': JSON.stringify({session_id:'rpc-test'}) } };
  try {
    const rpc = decorateCaptureRpc(async () => { if (error) throw error; return result; }, (...args) => observations.push(args));
    const setup = await rpc({type:'setup'});
    assert.ok(setup.methods.includes('compat_status'));
    assert.deepEqual(await rpc({type:'execute',method:'compat_status'}), {captureReminder:'on-result',polling:false,nativeReleaseAvailable:true});
    const capture = {type:'execute',method:'get_window_state',args:[{}]};
    result = {screenshots:['image']};
    assert.equal(await rpc(capture),result);
    assert.equal(observations[0][0].session_id,'rpc-test');
    await rpc({...capture,args:[{include_screenshot:false}]});
    await rpc({type:'execute',method:'list_windows'});
    result = {};
    await rpc(capture);
    assert.equal(observations.length,1);
    error = failure;
    await assert.rejects(rpc(capture), e => e === failure);
    assert.equal(observations.length,2);
    assert.equal(observations[1][1],failure);
  } finally { globalThis.nodeRepl = previous; }
});
