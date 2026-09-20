'use strict';
const $=id=>document.getElementById(id);
let current=null, pending=null;
const sampleQuestion='帮我看看今天还有哪些事，怎么安排比较好？';
const sampleReply='今天还有两件事，可以这样安排：\n\n14:00 · 整理周会 PPT\n先把本周进展、关键数据和需要讨论的问题收拢，留一点时间检查内容。\n\n16:00 · 和 mm 确认设计稿\n把待确认的页面和问题提前列好，沟通起来会更轻松。\n\n浇水在明天，逛超市在周六，今天先不用惦记。接口联调已经完成了。\n\n如果时间不合适，也可以继续告诉我你想怎么调整。';
function busy(value){$('send').classList.toggle('busy',value);$('send').ariaLabel=value?'停止任务':'发送';$('send').title=value?'停止任务':'发送 · Enter';$('send').disabled=!value&&!$('input').value.trim();$('input').readOnly=value;}
function resize(){const input=$('input');input.style.height='auto';input.style.height=Math.min(input.scrollHeight,60)+'px';busy(pending!==null);}
function showList(){ $('list').hidden=false;$('detail').hidden=true;$('back').hidden=true;$('count').hidden=false;$('panelTitle').textContent='待办'; }
function showDetail(){if(!current)return;document.querySelector('.todo-panel').hidden=false;$('frog').ariaExpanded='true';$('list').hidden=true;$('detail').hidden=false;$('back').hidden=false;$('count').hidden=true;$('panelTitle').textContent='消息';$('detailQuestion').textContent=current.question;$('detailReply').replaceChildren();for(const text of current.reply.split('\n\n')){const p=document.createElement('p');p.className='reply-paragraph';p.textContent=text;$('detailReply').append(p)}$('detail').scrollTop=0;}
function receive(question,reply){current={question,reply};$('bubbleText').textContent=reply.replace(/\n+/g,' ');$('bubble').hidden=false;if(!$('detail').hidden)showDetail();}
$('composer').onsubmit=e=>{e.preventDefault();if(pending!==null){clearTimeout(pending);pending=null;busy(false);return;}const question=$('input').value.trim();if(!question)return;pending=setTimeout(()=>{pending=null;receive(question,question===sampleQuestion?sampleReply:'收到，你说的是「'+question+'」。\n\n这是交互演示中的模拟回复，用来预览新消息气泡和全文面板，不会修改真实待办。\n\n回复先出现在青蛙左上角，最多展示三行。点击气泡，这里会展示当前消息的完整内容；点击左上方返回箭头，就能回到待办列表。');$('input').value='';resize();},900);busy(true);};
$('input').addEventListener('input',resize);$('input').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing&&pending===null){e.preventDefault();$('composer').requestSubmit();}});
$('bubble').onclick=showDetail;$('back').onclick=showList;
function toggle(){const panel=document.querySelector('.todo-panel');panel.hidden=!panel.hidden;$('frog').ariaExpanded=String(!panel.hidden);}
$('frog').onclick=toggle;$('close').onclick=toggle;
$('demoReply').onclick=()=>receive(sampleQuestion,sampleReply);
$('reset').onclick=()=>{clearTimeout(pending);pending=null;current=null;$('bubble').hidden=true;$('input').value='';resize();showList();document.querySelector('.todo-panel').hidden=false;$('frog').ariaExpanded='true';};
receive(sampleQuestion,sampleReply);
