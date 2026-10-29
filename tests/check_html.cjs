const fs=require('node:fs');
const text=fs.readFileSync('public/index.html','utf8');
let count=0;
for(const m of text.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)){
 if(!m[1].trim())continue;
 try{new Function(m[1]);count++}
 catch(e){console.error('Invalid inline game script',count,e);process.exit(1)}
}
if(count<10)throw new Error('Missing original Amberlings game scripts');
for(const source of ['public/online-bridge.js','public/online-config.js'])new Function(fs.readFileSync(source,'utf8'));
console.log('PASS',count,'original game scripts and online bridge JS syntax');
