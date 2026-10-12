export function classifyCaptureError(error) {
  const message = String(error?.message ?? error);
  if (/SetIsBorderRequired.*(?:0x80004002|No such interface|not supported)/i.test(message)) return 'border-interface';
  if (/FrameArrived timed out|window capture timed out/i.test(message)) return 'capture-timeout';
}

export function createCaptureHealth({ notify, now = Date.now, report = () => {} }) {
  const sessions = new Map();
  return async function observe(metadata, error) {
    const id = metadata?.session_id;
    if (typeof id !== 'string' || !id) return;
    const time = now();
    const previous = sessions.get(id);
    const kind = error === undefined ? undefined : classifyCaptureError(error);
    if (error !== undefined && !kind) {
      // An unrelated error breaks the sequence of confirmed capture failures.
      sessions.delete(id);
      return;
    }
    if (!kind) { sessions.delete(id); return; }
    const continuing = previous?.kind === kind && time - previous.time <= 600000 && time >= previous.time;
    const current = { kind, time, count: continuing ? previous.count + 1 : 1, alerted: continuing && previous.alerted };
    sessions.set(id, current);
    if (current.count < 2 || current.alerted) return;
    const message = `Windows CU 截图在会话 ${id} 中连续两次失败（${kind}）。请修复实际截图故障。`;
    try {
      await notify(message);
      current.alerted = true;
      report(message);
    } catch (failure) {
      report(`${message} 桌面提醒未送达：${String(failure?.message ?? failure)}`);
    }
  };
}
