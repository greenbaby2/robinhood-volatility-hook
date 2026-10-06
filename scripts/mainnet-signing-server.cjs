// Local static server only. No private-key handling, transaction signing, or network proxy.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const files = {'/':['index.html','text/html; charset=utf-8'], '/app.js':['app.js','text/javascript'],
  '/manifest.json':['manifest.json','application/json']};
const server = http.createServer((req,res) => {
  if (req.headers.host !== '127.0.0.1:8766' && req.headers.host !== 'localhost:8766') {
    res.writeHead(403); return res.end();
  }
  const f = files[req.url];
  if (req.method !== 'GET' || !f) {res.writeHead(404); return res.end('Not found');}
  try {
    const body = fs.readFileSync(req.url === '/manifest.json' ? path.join(__dirname,'..','signer-state','mainnet-manifest.json') : path.join(__dirname,'..','mainnet-signing',f[0]));
    res.writeHead(200, {'Content-Type':f[1], 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff',
      'Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'"});
    res.end(body);
  } catch {res.writeHead(404);res.end('Generate the signing manifest first.');}
});
server.listen(8766,'127.0.0.1',()=>console.log('Mainnet wallet signing: http://127.0.0.1:8766'));
