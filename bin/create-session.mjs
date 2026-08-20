#!/usr/bin/env node
// create-session.mjs — 按指定 id 预建 DSH 会话 (官方 JSONL 格式, 与 store 完全一致).
//
// 用途: dsh --profile tui --resume <id> 只能恢复已存在的会话; 本脚本在启动前用
//       官方持久化格式 (sessions/<projectKey>/<encode(id)>/session.jsonl.zstd,
//       header 行 + zstd 压缩) 预建一个空会话, 让 resume 拿到稳定的任务会话 id
//       (kb-<task-id>)。已存在则跳过, 绝不覆盖历史。
//
// 用法: node create-session.mjs <session-id> <absolute-cwd>
//   <cwd> 必须与后续 dsh 启动时的进程 cwd 一致 (会话按 cwd 分组).
import { zstdCompressSync } from 'node:zlib'
import { mkdirSync, existsSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join, isAbsolute } from 'node:path'

// 与 dsh-session-persistence-jsonl 的 projectKey(cwd) 一致:
// 路径分隔符 -> '-', 非 [A-Za-z0-9._-] 字符 -> ~XXXX, 首尾加 --.
function projectKey(cwd) {
  let readable = ''
  let separatorRun = false
  for (let i = 0; i < cwd.length; i++) {
    const code = cwd.charCodeAt(i)
    const ch = String.fromCharCode(code)
    if (ch === '/' || ch === '\\' || ch === ':') {
      if (!separatorRun) readable += '-'
      separatorRun = true
    } else if (ch !== '~' && /^[A-Za-z0-9._-]$/.test(ch)) {
      readable += ch
      separatorRun = false
    } else {
      readable += '~' + code.toString(16).toUpperCase().padStart(4, '0')
      separatorRun = false
    }
  }
  return '--' + (readable.replace(/^-+/, '') || 'root').slice(0, 251) + '--'
}

// 与 dsh-session-persistence-jsonl 的 encodeSegment(id) 一致.
function encodeSegment(raw) {
  if (raw.length === 0) throw new Error('cannot encode an empty path segment')
  if (raw === '.') return '~002E'
  if (raw === '..') return '~002E~002E'
  let out = ''
  for (let i = 0; i < raw.length; i++) {
    const code = raw.charCodeAt(i)
    const ch = String.fromCharCode(code)
    if (ch !== '~' && /^[A-Za-z0-9._-]$/.test(ch)) out += ch
    else out += '~' + code.toString(16).toUpperCase().padStart(4, '0')
  }
  return out
}

const [, , sessionId, cwd] = process.argv
if (!sessionId || !cwd || !isAbsolute(cwd)) {
  console.error('用法: create-session.mjs <session-id> <absolute-cwd>')
  process.exit(2)
}
const dshHome = process.env.DSH_HOME || join(homedir(), '.dsh')
const dir = join(dshHome, 'sessions', projectKey(cwd), encodeSegment(sessionId))
const log = join(dir, 'session.jsonl.zstd')
if (existsSync(log)) {
  console.log(`session ${sessionId} 已存在: ${log} (跳过, 保留历史)`)
  process.exit(0)
}
// 存储格式 header (dsh-session-persistence-jsonl isHeaderLine):
//   type: "session" / version: 0 / id / createdAt(ms) / delegationDepth>=0 / cwd(绝对路径)
const header = JSON.stringify({
  type: 'session',
  version: 0,
  id: sessionId,
  createdAt: Date.now(),
  delegationDepth: 0,
  cwd,
}) + '\n'
mkdirSync(dir, { recursive: true, mode: 0o700 })
writeFileSync(log, zstdCompressSync(Buffer.from(header, 'utf8')), { mode: 0o600 })
console.log(`已创建会话 ${sessionId}: ${log}`)
