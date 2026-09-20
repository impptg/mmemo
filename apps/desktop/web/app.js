'use strict';
const $ = id => document.getElementById(id);
const native = message => window.webkit.messageHandlers.mmemo.postMessage(message);
const surface=location.hash.slice(1) || 'list';
document.body.dataset.surface=surface;
let currentAccount=null, members=[];
let tasks = [], completedOpen = false, busy = false, modelName = null, latestReply = null;
let draftReady = false;
function snapshotDraft() {
  const parts=[];
  const text=value=>{if(value) {if(parts.at(-1)?.kind==='text') parts.at(-1).text+=value;else parts.push({kind:'text',text:value});}};
  function visit(node) {
    if(node.nodeType===Node.TEXT_NODE) {text(node.textContent);return;}
    if(node.nodeType!==Node.ELEMENT_NODE) return;
    if(node.classList.contains('task-token')) {parts.push({kind:'task',id:node.dataset.taskId,title:node.title});return;}
    if(node.tagName==='BR') {text('\n');return;}
    if(['DIV','P'].includes(node.tagName) && parts.length) text('\n');
    for(const child of node.childNodes) visit(child);
  }
  for(const node of $('chatInput').childNodes) visit(node);
  return {version:1,parts};
}
function persistDraft() {
  if(surface==='list' && draftReady) native({action:'draft',draft:snapshotDraft()});
}
function restoreDraft(draft) {
  const input=$('chatInput');input.replaceChildren();
  for(const part of draft.parts) {
    if(part.kind==='text') input.append(document.createTextNode(part.text));
    else if(part.kind==='task') {
      const token=document.createElement('span');token.className='task-token';token.contentEditable='false';
      token.dataset.taskId=part.id;token.title=part.title;token.textContent=part.title;
      token.setAttribute('aria-label',part.title);input.append(token);
    }
  }
  draftReady=true;resizeComposer();
}
function setBusy(value) {
  busy=value;
  const button=$('sendButton');
  button.classList.toggle('stopping',value);
  button.ariaLabel=value ? '停止任务' : '发送';
  button.title=value ? '停止任务' : '发送 · Enter';
  button.disabled=!value && !composerText().trim();
  $('chatInput').contentEditable=String(!value);
  $('chatInput').setAttribute('aria-readonly',String(value));
  resizeComposer();
}
function render() {
  const list = $('list'); list.replaceChildren();
  const pending=tasks.filter(t=>!t.done), completed=tasks.filter(t=>t.done);
  const recent=document.createElement('section'); recent.className='todo-group'; recent.ariaLabel='最近';
  $('recentHeading').textContent=`最近 · ${pending.length}`;
  $('recentHeading').hidden=!tasks.length || !$('detail').hidden;
  const finished=document.createElement('details'); finished.className='todo-group completed-group'; finished.open=completedOpen;
  const summary=document.createElement('summary'); summary.className='group-heading'; summary.textContent=`已完成 · ${completed.length}`; const chevron=document.createElement('img'); chevron.className='group-chevron'; chevron.src='arrow-right-s-line.svg'; chevron.alt=''; summary.append(chevron); finished.append(summary);
  let headerToggle;
  if(!pending.length && completed.length) {
    summary.hidden=true; finished.style.marginTop='0';
    headerToggle=document.createElement('button'); headerToggle.type='button'; headerToggle.className='group-toggle';
    headerToggle.textContent=`已完成 · ${completed.length}`; headerToggle.append(chevron.cloneNode());
    finished.id='completedTasks'; headerToggle.setAttribute('aria-controls',finished.id);
    headerToggle.setAttribute('aria-expanded',String(finished.open));
    headerToggle.onclick=()=>{completedOpen=finished.open=!finished.open;headerToggle.setAttribute('aria-expanded',String(finished.open));};
    $('recentHeading').replaceChildren(headerToggle);
  }
  finished.addEventListener('toggle',()=>{if(list.contains(finished)) {completedOpen=finished.open;headerToggle?.setAttribute('aria-expanded',String(finished.open));}});
  if(pending.length) list.append(recent);
  if(completed.length) list.append(finished);
  for (const t of [...pending,...completed]) {
    const row = document.createElement('article'); row.className = `todo${t.done ? ' completed' : ''}`;
    row.dataset.taskId=t.id; row.tabIndex=0; row.setAttribute('role','group');
    row.title='点击引用 · ⌘ 点击多选';
    row.onclick=e=>selectTask(t,e.metaKey || e.ctrlKey);
    row.onkeydown=e=>{if(e.target===row && (e.key==='Enter' || e.key===' ')) {e.preventDefault();selectTask(t,e.metaKey || e.ctrlKey);}};
    const check = document.createElement('button'); check.type='button'; check.className = `state${t.done ? ' done' : ''}`;
    check.setAttribute('role','checkbox'); check.setAttribute('aria-checked',String(t.done));
    check.ariaLabel = `${t.done ? '标记未完成' : '标记完成'}：${t.title}`; check.title=t.done?'标记未完成':'标记完成';
    check.onclick=e=>{e.stopPropagation();if(busy)return;check.disabled=true;native({action:'setDone',id:t.id,done:!t.done});};
    if (t.done) { const img = document.createElement('img'); img.src = 'icons/check.png'; img.alt = ''; check.append(img); }
    const title = document.createElement('span'); title.className = 'task-title'; title.textContent = t.title;
    const avatars=document.createElement('span'); avatars.className='avatars';
    const people=t.participants || (t.createdBy ? [t.createdBy] : [null]);
    for(const uid of people) {
      const owner=members.find(m=>m.uid===uid);
      const raccoon=owner ? owner.avatar==='raccoon' : t.member==='partner';
      const avatar=document.createElement('span'); avatar.className=`avatar ${raccoon?'partner':'me'}`;
      avatar.title=owner ? `${owner.username} · ${raccoon?'小浣熊':'小青蛙'}` : (raccoon?'另一位成员 · 小浣熊':'我 · 小青蛙');
      avatar.setAttribute('role','img'); avatar.setAttribute('aria-label',avatar.title);
      const portrait=document.createElement('img'); portrait.src='assets/avatar-pair-love-white.png'; portrait.alt=''; avatar.append(portrait);
      avatars.append(avatar);
    }
    const time = document.createElement('span'); time.className = 'time'; time.textContent = Model.dueLabel(t.due).replace(' ', '\n');
    if(t.due && !t.done && new Date(t.due)<new Date()) {time.classList.add('overdue'); time.title='已到期';}
    row.append(check,title,avatars,time); (t.done?finished:recent).append(row);
  }
  syncSelection();
  if(surface==='list') native({action:'reminders'});
}
let statusTimer=null, statusText=null;
window.mmemo = {
  snapshotDraft, restoreDraft,
  prepareToQuit() { $('chatInput').contentEditable='false'; return snapshotDraft(); },
  heartSending(value) { $('sendHeart').disabled=value; },
  identity(account, users) {
    currentAccount=account;members=users;
    $('accountStatus').hidden=!account;
    $('accountStatus').textContent=account ? `${account} · 连接中` : '';
    if(surface==='list') render();
  },
  connection(text) { if(currentAccount) $('accountStatus').textContent=`${currentAccount} · ${text}`; },
  load(data, error) {
    try { if(error) throw new Error(error); tasks=Model.validate(data); }
    catch(e) { if(surface==='list') showDetail(e.message+' · 原文件已保留', true); }
    render();
  },
  configure(name) { modelName=name; },
  replied(reply, data, error) {
    setBusy(false);
    if(error) return;
    else {
      try { tasks=Model.validate(data); $('chatInput').replaceChildren(); render(); window.mmemo.latest(reply); resizeComposer(); }
      catch(e) { if(surface==='list') showDetail('列表刷新失败，请重新打开应用核对。',true); }
    }
  },
  latest(text) {
    if(typeof text!=='string' || !text.trim()) return;
    latestReply=text;
    $('latestMessage').disabled=false;
    if(!$('detail').hidden) showDetail(text);
  },
  status(text) {
    const label=$('bubbleText');
    if(statusText===text) return;
    statusText=text; clearInterval(statusTimer); statusTimer=null;
    label.textContent=text.endsWith('...') ? text.slice(0,-3) : text;
    if(text.endsWith('...')) {
      const dots=document.createElement('span'); dots.className='status-dots';
      dots.textContent='.'; label.append(dots);
      if(surface==='bubble') {
        let count=1;
        statusTimer=setInterval(()=>{count=count%3+1;dots.textContent='.'.repeat(count);},400);
      }
    }
    $('replyBubble').setAttribute('aria-label', `${text}，点击查看完整消息`);
    label.setAttribute('aria-hidden','true');
  },
  showLatest() { if(latestReply!==null) showDetail(latestReply); },
  stopped() { setBusy(false); },
  opened() {render();},
};
function showDetail(text, error=false) {
  $('latestMessage').dataset.view='message';
  $('latestMessage').ariaLabel='返回待办'; $('latestMessage').title='返回待办'; $('latestMessage').disabled=false;
  $('list').hidden=true; $('detail').hidden=false;
  $('recentHeading').hidden=true; $('panelTitle').hidden=false;
  $('panelTitle').textContent=error?'提示':'消息';
  document.querySelector('.message-meta').hidden=error;
  $('detailText').textContent=text; $('detail').scrollTop=0;
}
function showList() {
  $('latestMessage').dataset.view='todo';
  $('latestMessage').ariaLabel='最新消息'; $('latestMessage').title='最新消息'; $('latestMessage').disabled=latestReply===null;
  $('list').hidden=false; $('detail').hidden=true;
  $('recentHeading').hidden=!tasks.length; $('panelTitle').hidden=true;
}
$('replyBubble').onclick=()=>native({action:'showLatest'});
$('latestMessage').onclick=()=>{if(!$('detail').hidden)showList();else native({action:'showLatest'});};
$('replyBubble').addEventListener('mouseenter',()=>native({action:'bubbleHover',hovered:true}));
$('replyBubble').addEventListener('mouseleave',()=>native({action:'bubbleHover',hovered:false}));
$('chatForm').onsubmit = e => {
  e.preventDefault();
  const text=composerText().trim();
  if (busy) { native({action:'stop'}); return; }
  if (!text) return;
  if(text.length>2000) { native({action:'inputError',message:'输入和事项引用合计不能超过 2000 个字符，内容已保留。'}); return; }
  if([...$('chatInput').querySelectorAll('.task-token')].some(t=>!tasks.some(task=>task.id===t.dataset.taskId))) {
    native({action:'inputError',message:'引用的事项已不存在，请移除后重新选择。'}); return;
  }
  if(!modelName) { native({action:'inputError',message:'AI 还没有连接。你的输入已保留。'}); return; }
  setBusy(true);
  native({action:'chat',text});
};
function resizeComposer() {
  const empty=!composerText().trim();
  $('chatInput').dataset.empty=String(empty);
  $('sendButton').disabled=!busy && empty;
  syncSelection();
  persistDraft();
}
function composerText() {
  const copy=$('chatInput').cloneNode(true);
  for(const token of copy.querySelectorAll('.task-token')) {
    const title=token.title.replace(/[\\[\]]/g,'\\$&');
    token.replaceWith(document.createTextNode(`[/${title}](todo:${encodeURIComponent(token.dataset.taskId)})`));
  }
  for(const br of copy.querySelectorAll('br')) br.replaceWith('\n');
  for(const block of copy.querySelectorAll('div,p')) block.prepend('\n');
  return copy.textContent;
}
function syncSelection() {
  const selected=new Set([...$('chatInput').querySelectorAll('.task-token')].map(t=>t.dataset.taskId));
  for(const row of document.querySelectorAll('.todo')) {
    row.classList.toggle('selected',selected.has(row.dataset.taskId));
    row.setAttribute('aria-label',`${selected.has(row.dataset.taskId)?'已引用':'引用事项'}：${row.querySelector('.task-title').textContent}`);
    row.setAttribute('aria-disabled',String(busy));
    row.querySelector('.state').disabled=busy;
  }
}
function selectTask(task, multiple) {
  if(busy) return;
  const input=$('chatInput'), copy=input.cloneNode(true);
  // WebKit's trailing placeholder break is not part of the draft.
  if(copy.lastChild?.nodeName==='BR') copy.lastChild.remove();
  const selected=[...copy.querySelectorAll('.task-token')].map(t=>t.dataset.taskId);
  const ids=multiple ? (selected.includes(task.id) ? selected.filter(id=>id!==task.id) : [...selected,task.id]) : [task.id];
  for(const token of copy.querySelectorAll('.task-token')) {
    if(token.nextSibling?.nodeType===Node.TEXT_NODE && /^[ \u00a0]$/.test(token.nextSibling.textContent)) token.nextSibling.remove();
    token.remove();
  }
  if(!copy.textContent.trim()) copy.replaceChildren();
  // Keep typed text; replace references as one undoable browser edit.
  for(const id of ids) {
    const item=tasks.find(t=>t.id===id); if(!item) continue;
    const token=document.createElement('span'); token.className='task-token'; token.contentEditable='false';
    const letters=Array.from(new Intl.Segmenter('zh',{granularity:'grapheme'}).segment(item.title),part=>part.segment);
    token.dataset.taskId=id; token.textContent=letters.slice(0,5).join('')+(letters.length>5?'...':''); token.title=item.title;
    token.setAttribute('aria-label',item.title);
    copy.append(token,document.createTextNode(' '));
  }
  input.focus();
  const range=document.createRange();range.selectNodeContents(input);
  const selection=getSelection();selection.removeAllRanges();selection.addRange(range);
  document.execCommand('insertHTML',false,copy.innerHTML);
  while(input.lastChild?.nodeName==='BR') input.lastChild.remove();
  focusComposerEnd();
  resizeComposer(); input.scrollTop=input.scrollHeight;
}
function focusComposerEnd() {
  const input=$('chatInput'); input.focus();
  const range=document.createRange(); range.selectNodeContents(input); range.collapse(false);
  const selection=getSelection(); selection.removeAllRanges(); selection.addRange(range);
}
$('chatInput').addEventListener('click',e=>{
  if(busy || !$('chatInput').querySelector('.task-token')) return;
  const copy=$('chatInput').cloneNode(true);
  for(const token of copy.querySelectorAll('.task-token')) token.remove();
  if(!copy.textContent.trim() || e.target.closest('.task-token')) focusComposerEnd();
});
$('chatInput').addEventListener('input', resizeComposer);
$('chatInput').addEventListener('paste',e=>{
  e.preventDefault(); if(busy) return;
  document.execCommand('insertText',false,e.clipboardData.getData('text/plain'));
});
$('chatInput').addEventListener('drop',e=>e.preventDefault());
window.addEventListener('resize', resizeComposer);
$('chatInput').addEventListener('keydown', e => {
  if(!busy && e.key==='Enter' && e.shiftKey && !e.isComposing) {e.preventDefault();document.execCommand('insertLineBreak');return;}
  if(!busy && e.key==='Enter' && !e.shiftKey && !e.isComposing && e.keyCode!==229) {e.preventDefault();$('chatForm').requestSubmit();}
});
$('sendHeart').onclick=()=>native({action:'sendHeart'});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!e.isComposing)native({action:'hide'});});
window.addEventListener('error',e=>{native({action:'error',message:e.message});});
setBusy(false);
native({action:'ready'});
