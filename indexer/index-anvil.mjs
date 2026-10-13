// Indexes Executed events from a local anvil deployment (from monad e2e evidence) and reconciles.
import { createPublicClient, http, parseAbiItem, parseUnits } from 'viem'; import { foundry } from 'viem/chains'; import fs from 'node:fs';
import { newState, ingest, reconcile } from './reconcile.mjs';
const ev = JSON.parse(fs.readFileSync(process.argv[2]));
const pub = createPublicClient({ chain: foundry, transport: http('http://127.0.0.1:8545') });
const raw = await pub.getLogs({ address: ev.policyPilot, event: parseAbiItem('event Executed(bytes32 indexed requestId, address indexed recipient, uint256 amount, uint256 totalSpent)'), fromBlock: 0n });
const logs = raw.map(l => ({ ...l, ...l.args }));
const head = Number(await pub.getBlockNumber());
const s = ingest(newState(), [...logs, ...logs], head, 3); // deliberately double-deliver to exercise dedupe
const expected = ev.steps.filter(x => x.status === 'EXECUTED').map(x => ({ requestId: x.id, recipient: x.recipient, amount: parseUnits(x.amount, 18) }));
expected.push({ requestId: '0x' + 'ab'.repeat(32), recipient: ev.steps[0].recipient, amount: 1n }); // a payout that never happened
const r = reconcile(s, expected);
const out = { generatedAt: new Date().toISOString(), network: 'local anvil 31337', head, confirmationsRequired: 3, logsFetched: logs.length, ...r };
console.log(JSON.stringify(out, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
