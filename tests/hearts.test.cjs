const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const {heartInterval,heartCount} = require('../desktop/web/hearts.js');
assert.equal(heartInterval(1),25000);
assert.equal(heartInterval(10),300);
assert.equal(heartCount(1),1);
assert.equal(heartCount(10),4);
for(let level=2;level<=10;level++) {
  assert.ok(heartInterval(level)<heartInterval(level-1));
  assert.ok(heartCount(level)>=heartCount(level-1));
}
const nodes = [], timers = new Map(); let serial=0;
const reduced={matches:false, addEventListener(_, callback){this.change=callback}};
const context={window:{}, location:{search:''}, matchMedia:()=>reduced, Date, Math,
  setTimeout(fn){timers.set(++serial,fn);return serial},clearTimeout(id){timers.delete(id)},
  document:{body:{get childElementCount(){return nodes.length+1},append(n){nodes.push(n)}},
    querySelectorAll:()=>[...nodes],createElement:()=>({style:{setProperty(){}},addEventListener(){},remove(){nodes.splice(nodes.indexOf(this),1)}})}};
vm.runInNewContext(fs.readFileSync('desktop/web/hearts.js','utf8'),context);
const update=context.window.hearts.update;
update(0);assert.equal(nodes.length,0);
update(1);assert.equal(nodes.length,1);
update(1);assert.equal(nodes.length,1);assert.equal(timers.size,1);
update(10);assert.equal(nodes.length,4);
for(let i=0;i<30;i++){const [id,fn]=timers.entries().next().value;timers.delete(id);fn()}
assert.equal(nodes.length,12);assert.equal(timers.size,1);
update(0);assert.equal(nodes.length,0);assert.equal(timers.size,0);
reduced.matches=true;update(1);assert.equal(nodes.length,1);assert.equal(timers.size,0);
update(0);assert.equal(nodes.length,0);
console.log('PASS: level intervals and bursts, bounded particles, clear unread, reduced motion');
