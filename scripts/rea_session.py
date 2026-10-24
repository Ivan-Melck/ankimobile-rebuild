#!/usr/bin/env python3
"""Run a local REA MCP session from a JSONL request queue, retaining complete replies.
Usage: python3 scripts/rea_session.py <queue.jsonl> <output-directory>
Append {"label":"...", "tool":"...", "arguments":{...}}; close_binary closes the session.
No agent registration or global configuration is changed.
"""
import json, os, pathlib, signal, subprocess, sys, time
root = pathlib.Path(__file__).resolve().parents[1]
queue, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
output.mkdir(parents=True,exist_ok=True)
env = dict(os.environ)
env.setdefault('GHIDRA_INSTALL_DIR',str(root/'.tools/ghidra_12.1.4_PUBLIC'))
env.setdefault('REA_GHIDRA_STARTUP_TIMEOUT_MS','1800000')
env.setdefault('GHIDRA_HEADLESS_MAXMEM','4G')
env.setdefault('REA_GHIDRA_DECOMPILE_TIMEOUT_SECONDS','90')
err=(output/'rea-server.stderr.log').open('w')
p=subprocess.Popen([str(root/'.tools/node_modules/.bin/rea'),'--mcp'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=err,text=True,env=env)
request_id=0

def stop_session(signum, frame):
 raise SystemExit(128 + signum)
signal.signal(signal.SIGTERM, stop_session)

def rpc(method,params):
 global request_id
 request_id+=1
 p.stdin.write(json.dumps({'jsonrpc':'2.0','id':request_id,'method':method,'params':params})+'\n');p.stdin.flush()
 for line in p.stdout:
  try: response=json.loads(line)
  except json.JSONDecodeError: continue
  if response.get('id')==request_id:return response
 raise RuntimeError('REA server ended unexpectedly')

try:
 print(json.dumps(rpc('initialize',{'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'ankimobile-rebuild-investigation','version':'1.0'}})),flush=True)
 p.stdin.write(json.dumps({'jsonrpc':'2.0','method':'notifications/initialized'})+'\n');p.stdin.flush()
 (output/'rea-tools.json').write_text(json.dumps(rpc('tools/list',{}),indent=2)+'\n')
 completed=0
 while True:
  lines=queue.read_text().splitlines() if queue.exists() else []
  if completed>=len(lines):time.sleep(0.5);continue
  item=json.loads(lines[completed]);label=item['label'];name=item['tool']
  print(f'START {label} {name}',flush=True)
  result=rpc('tools/call',{'name':name,'arguments':item.get('arguments',{})})
  (output/f'{label}.json').write_text(json.dumps(result,indent=2)+'\n')
  completed+=1
  print(f'DONE {label}',flush=True)
  if name=='close_binary':break
finally:
 p.stdin.close()
 try:p.wait(timeout=20)
 except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=10)
 err.close()
