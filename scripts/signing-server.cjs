// Local static server only. No private-key handling, transaction signing, or network proxy.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const files = {'/':['index.html','text/html; charset=utf-8'], '/app.js':['app.js','text/javascript'],
  '/manifest.json':['manifest.json','application/json']};
const server = http.createServer((req,res) => {
  if (req.headers.host !== '127.0.0.1:8765' && req.headers.host !== 'localhost:8765') {
    res.writeHead(403); return res.end();
  }
  const f = files[req.url];
  if (req.method !== 'GET' || !f) {res.writeHead(404); return res.end('Not found');}
  try {
    res.writeHead(200, {'Content-Type':f[1], 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff',
      'Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'"});
    res.end(fs.readFileSync(path.join(__dirname,'..','signing',f[0])));
  } catch {res.writeHead(404);res.end('Generate the signing manifest first.');}
});
server.listen(8765,'127.0.0.1',()=>console.log('Testnet wallet signing: http://127.0.0.1:8765'));
