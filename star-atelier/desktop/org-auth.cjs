'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const owner = 'AradoLadies';
const repo = 'game';
const apiPath = '/repos/' + owner + '/' + repo;
async function api(route, token, method = 'GET', body) {
  const res = await fetch('https://api.github.com' + route, { method, headers: {
    Authorization: 'Bearer ' + token, Accept: 'application/vnd.github+json',
    'User-Agent': 'AradoLadies-Publisher', 'Content-Type': 'application/json'
  }, body: body === undefined ? undefined : JSON.stringify(body) });
  if (!res.ok) throw Error(method + ' ' + route + ': GitHub HTTP ' + res.status);
  return res.json();
}
function jwt() {
  const configFile = path.join(process.env.LOCALAPPDATA, 'AradoPublisher', 'org-app.json');
  const app = JSON.parse(fs.readFileSync(configFile, 'utf8').replace(/^\uFEFF/, ''));
  if (app.owner !== owner || !Number.isSafeInteger(app.id)) throw Error('Invalid organization app configuration.');
  const ps = '$ErrorActionPreference="Stop";$value=ConvertTo-SecureString ([Console]::In.ReadToEnd());[Console]::Write([Net.NetworkCredential]::new("",$value).Password)';
  const key = spawnSync('powershell.exe', ['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(ps,'utf16le').toString('base64')], {
    env: { ...process.env, PSModulePath: path.join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'Modules') },
    input: app.protectedKey, encoding: 'utf8', windowsHide: true
  });
  if (key.status !== 0) throw Error('Cannot unlock the publishing key for this Windows account.');
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const data = encode({ alg:'RS256',typ:'JWT' }) + '.' + encode({ iss:app.id,iat:now-60,exp:now+480 });
  return data + '.' + crypto.sign('RSA-SHA256',Buffer.from(data),key.stdout).toString('base64url');
}
async function authenticate(permissions) {
  const signature = jwt();
  const app = await api('/app', signature);
  if (app.owner?.login !== owner) throw Error('App owner does not match the game organization.');
  const install = await api(apiPath+'/installation',signature);
  const result = await api('/app/installations/'+install.id+'/access_tokens',signature,'POST',
    { repositories:[repo], permissions });
  return result.token;
}
async function main() {
  const action = process.argv[2];
  if (action === 'make-public') {
    const token = await authenticate({ administration:'write' });
    const current = await api(apiPath, token);
    if (current.private) await api(apiPath,token,'PATCH',{ private:false });
    console.log('Public repository: '+owner+'/'+repo);
    return;
  }
  if (action !== 'get') return; // Git also calls helpers with store and erase.
  const fields = new URLSearchParams();
  for (const line of fs.readFileSync(0,'utf8').split(/\r?\n/)) {
    const at = line.indexOf('=');
    if (at > 0) fields.set(line.slice(0,at),line.slice(at+1));
  }
  if (fields.get('protocol') !== 'https' || fields.get('host') !== 'github.com' ||
      !['aradoladies/game','aradoladies/game.git'].includes((fields.get('path')||'').toLowerCase())) return;
  const token = await authenticate({ contents:'write',workflows:'write' });
  process.stdout.write('username=x-access-token\npassword='+token+'\n\n');
}
main().catch(err=>{console.error(err.message);process.exitCode=1;});
