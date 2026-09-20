/* Shared validation for disk load and every edit. No HTML is accepted as markup. */
const Model = {
  validate(tasks) {
    if (!Array.isArray(tasks) || tasks.length > 10000) throw new Error('待办文件格式不正确');
    const ids = new Set();
    return tasks.map(t => {
      if (!t || typeof t.id !== 'string' || !t.id || t.id.length > 100 || ids.has(t.id)) throw new Error('待办标识为空或重复');
      ids.add(t.id);
      if (typeof t.title !== 'string' || !t.title.trim() || t.title.length > 200) throw new Error('标题应为 1–200 个字符');
      if (typeof t.done !== 'boolean') throw new Error('待办状态不正确');
      if (typeof t.due !== 'string') throw new Error('日期不正确');
      if (t.due) {
        if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(t.due)) throw new Error('日期不正确');
        const d = new Date(t.due), parts = t.due.match(/\d+/g).map(Number);
        if (!Number.isFinite(d.getTime()) || d.getFullYear() !== parts[0] || d.getMonth()+1 !== parts[1] || d.getDate() !== parts[2] || d.getHours() !== parts[3] || d.getMinutes() !== parts[4]) throw new Error('日期不正确');
      }
      if (t.member != null && !["me","partner"].includes(t.member)) throw new Error("待办成员不正确");
      if(t.createdBy != null && (typeof t.createdBy !== 'string' || t.createdBy.length>100)) throw new Error('创建者不正确');
      if(t.participants != null && (!Array.isArray(t.participants) || t.participants.length<1 || t.participants.length>2 || new Set(t.participants).size!==t.participants.length || t.participants.some(uid=>typeof uid!=='string' || !uid || uid.length>100))) throw new Error('参与人不正确');
      return {...(t.participants == null ? {} : {participants:[...t.participants]}),...(t.createdBy == null ? {} : {createdBy:t.createdBy}),id:t.id, title:t.title.trim(), due:t.due, done:t.done, ...(t.member == null ? {} : {member:t.member})};
    });
  },
  dueLabel(value, now = new Date()) {
    if (!value) return '';
    const date = new Date(value), tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate()+1);
    const sameDay = d => date.getFullYear() === d.getFullYear() && date.getMonth() === d.getMonth() && date.getDate() === d.getDate();
    const time = value.slice(11);
    return sameDay(now) ? time : sameDay(tomorrow) ? `明天 ${time}` : `${date.getMonth()+1}/${date.getDate()} ${time}`;
  }
};
