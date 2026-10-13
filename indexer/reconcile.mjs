// Pure reconciliation core: ingest Executed logs (possibly duplicated, delayed, or reorged out),
// compare against the expected payout ledger, and classify each request.
export function ingest(state, logs, headBlock, confirmations) {
  for (const l of logs) {
    const k = `${l.transactionHash}:${l.logIndex}`;
    if (l.removed) { state.events.delete(k); continue; }            // reorg removal
    if (state.events.has(k)) { state.duplicates++; continue; }      // duplicate delivery
    state.events.set(k, { requestId: l.requestId, recipient: l.recipient.toLowerCase(), amount: BigInt(l.amount), block: Number(l.blockNumber) });
  }
  state.head = headBlock; state.confirmations = confirmations;
  return state;
}
export const newState = () => ({ events: new Map(), duplicates: 0, head: 0, confirmations: 0 });
export function reconcile(state, expected) {
  const byId = new Map();
  for (const e of state.events.values()) { const a = byId.get(e.requestId) ?? []; a.push(e); byId.set(e.requestId, a); }
  const rows = [];
  for (const x of expected) {
    const evs = byId.get(x.requestId) ?? []; byId.delete(x.requestId);
    let status;
    if (evs.length === 0) status = 'MISSING';
    else if (evs.length > 1) status = 'DOUBLE_EXECUTION';
    else if (evs[0].recipient !== x.recipient.toLowerCase() || evs[0].amount !== BigInt(x.amount)) status = 'MISMATCH';
    else if (state.head - evs[0].block + 1 < state.confirmations) status = 'PENDING_CONFIRMATIONS';
    else status = 'MATCHED';
    rows.push({ requestId: x.requestId, status });
  }
  for (const [id] of byId) rows.push({ requestId: id, status: 'UNEXPECTED' });
  return { rows, duplicatesIgnored: state.duplicates };
}
