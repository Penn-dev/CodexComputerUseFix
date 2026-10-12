import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { transformNativeModule } from './bootstrap.mjs';
test('unrelated and unrecognized modules pass through without disabling official CU', () => {
  assert.equal(transformNativeModule(pathToFileURL(process.cwd()+'/example/app.js').href,'stock'), 'stock');
  assert.equal(transformNativeModule(pathToFileURL(process.cwd()+'/example/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/windows/internal/computer_use_client_base.js').href,'unknown'),'unknown');
});
test('current official native client gains cleanup without any disk modification', {skip:!process.env.CU_TEST_MODULES}, async () => {
  const root=process.env.CU_TEST_MODULES;
  const filename=root+'/\u0040oai/sky/dist/project/cua/sky_js/src/targets/windows/internal/computer_use_client_base.js';
  const before=await readFile(filename);
  const { WindowsComputerUseClient }=await import(pathToFileURL(root+'/\u0040oai/sky/dist/project/cua/sky_js/src/targets/windows/internal/computer_use_client.js'));
  const calls=[];
  const client=new WindowsComputerUseClient({transport:{async request(method){calls.push(method);return []},async close(){calls.push('close')}}});
  assert.ok(Object.keys(client).includes('end_turn'));
  await client.list_windows();await client.end_turn();
  assert.deepEqual(calls,['list_windows','end_turn','close']);
  assert.deepEqual(await readFile(filename),before);
});

test('official supervisor loads repair under the desktop plugin trust boundary', {skip:!process.env.CU_TEST_MODULES || !process.env.CU_TEST_CLI}, async () => {
  const bin = path.dirname(process.env.CU_TEST_MODULES);
  const plugins = path.join(process.env.USERPROFILE,'.codex','plugins');
  const receipt = JSON.parse(await readFile(path.join(process.env.ProgramData,'OpenAI','Codex','config.toml.codex-cu-native.json'),'utf8'));
  assert.ok(receipt.destination.toLowerCase().startsWith((plugins+path.sep).toLowerCase()));
  const wrapper = receipt.files.find(file => path.basename(file.target)==='worker-wrapper.cjs').target;
  const env = {...process.env,
    NODE_REPL_NODE_PATH:path.join(bin,'node.exe'),
    NODE_REPL_NODE_MODULE_DIRS:process.env.CU_TEST_MODULES,
    NODE_REPL_TRUSTED_CODE_PATHS:plugins+';'+process.env.CU_TEST_MODULES,
    NODE_REPL_TRUSTED_SERVICES:JSON.stringify({sky:'@oai/sky/service'}),
    NODE_REPL_WORKER_WRAPPER:JSON.stringify([process.execPath,wrapper]),
    CODEX_CLI_PATH:process.env.CU_TEST_CLI,
  };
  const child = spawn(path.join(bin,'node_repl.exe'),[],{env,stdio:['pipe','pipe','pipe'],windowsHide:true});
  let output='',diagnostics='',settled=false;
  const result = await new Promise((resolve,reject) => {
    const timer = setTimeout(()=>{child.kill();reject(new Error('Official startup timed out: '+diagnostics));},20000);
    const send = value => child.stdin.write(JSON.stringify(value)+'\n');
    child.once('error',error=>{clearTimeout(timer);reject(error)});
    child.stderr.on('data',chunk=>{diagnostics+=chunk});
    child.once('exit',code=>{clearTimeout(timer);if(!settled)reject(new Error('Official supervisor exited before replying ('+code+'): '+diagnostics))});
    child.stdout.on('data',chunk=>{
      output+=chunk;let newline;
      while((newline=output.indexOf('\n'))>=0){
        const line=output.slice(0,newline);output=output.slice(newline+1);
        let response;try{response=JSON.parse(line)}catch{continue}
        if(response.id===1){
          send({jsonrpc:'2.0',method:'notifications/initialized'});
          send({jsonrpc:'2.0',id:2,method:'tools/call',params:{name:'js',arguments:{code:"const {sky}=await import('@oai/sky'); nodeRepl.write(JSON.stringify(await sky.compat_status()));",title:'Read CU loader status'}}});
        }else if(response.method==='elicitation/create'){
          clearTimeout(timer);child.kill();reject(new Error('Unexpected approval request during read-only startup'));
        }else if(response.id===2){
          settled=true;clearTimeout(timer);child.stdin.end();resolve(response.result);
        }
      }
    });
    send({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2024-11-05',capabilities:{},clientInfo:{name:'cu-startup-validation',version:'1'}}});
  });
  assert.equal(result.isError,false,JSON.stringify(result));
  const status=JSON.parse(result.content.filter(item=>item.type==='text').map(item=>item.text).join(''));
  assert.deepEqual(status,{captureReminder:'on-result',nativeReleaseAvailable:true,polling:false});
});
