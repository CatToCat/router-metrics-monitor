#!/usr/bin/env node
/* =============================================================
 * git-push.js  -- push script (run with Node on a Windows PC)
 *
 * Commits the data accumulated by router-metrics-collect.js and pushes it
 * to the remote. Triggered once per hour by Windows Task Scheduler.
 *
 * Prerequisites: the repo already has a configured remote (HTTPS with token
 *       or SSH both work), and router-metrics-collect.js has produced data.
 * ============================================================= */

'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const REPO_DIR = path.resolve(__dirname, '..');
const ENV_FILE = path.join(REPO_DIR, '.env');
const LOG_DIR = path.join(REPO_DIR, 'logs');
const LOG_FILE = path.join(LOG_DIR, 'push.log');

// Format a Date as "YYYY-MM-DD HH:MM:SS" in China Standard Time (UTC+8),
// independent of the machine's local timezone.
function fmtCST(d = new Date()) {
  const t = new Date(d.getTime() + 8 * 3600 * 1000);
  return t.toISOString().slice(0, 19).replace('T', ' ');
}

function log(msg) {
  const line = `${fmtCST()} ${msg}`;
  console.log(line);
  try {
    if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });
    fs.appendFileSync(LOG_FILE, line + '\n');
  } catch (_) {}
}

// Read branch (default main)
let branch = 'main';
if (fs.existsSync(ENV_FILE)) {
  for (const raw of fs.readFileSync(ENV_FILE, 'utf8').split(/\r?\n/)) {
    const m = raw.trim().match(/^GIT_BRANCH\s*=\s*(.+)$/);
    if (m) branch = m[1].trim();
  }
}

function git(args) {
  return execFileSync('git', args, { cwd: REPO_DIR, encoding: 'utf8' });
}

try {
  git(['add', 'public/data', 'logs']);
  let changed = false;
  try { git(['diff', '--cached', '--quiet']); } catch (_) { changed = true; }
  if (changed) {
    git(['commit', '-m', `data: hourly sync ${fmtCST()}`]);
    log('committed hourly data');
  }

  // Push an earlier commit too if the previous hourly network attempt failed.
  let ahead = 'unknown';
  try { ahead = git(['rev-list', '--count', `origin/${branch}..HEAD`]).trim(); } catch (_) {}

  if (ahead === '0') { log('nothing to push'); process.exit(0); }

  git(['push', 'origin', branch]);
  log(`pushed OK (ahead was ${ahead} commits)`);
} catch (e) {
  log('push FAILED: ' + (e.stderr || e.message || e).toString().trim());
  process.exit(1);
}
