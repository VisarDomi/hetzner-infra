#!/usr/bin/env node
//
// GitHub webhook receiver — triggers deploy.sh on push to main
//
// Verifies HMAC-SHA256 signature from GitHub. Runs deploy.sh in background
// so the HTTP response returns immediately.
//
// Usage: WEBHOOK_SECRET=xxx node webhook.js
//
import { createServer } from 'node:http';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { appendFileSync } from 'node:fs';

const PORT = 9876;
const __dirname = dirname(fileURLToPath(import.meta.url));
const DEPLOY_SCRIPT = join(__dirname, 'deploy.sh');
const LOG_FILE = join(__dirname, 'logs', 'webhook.log');

const SECRET = process.env.WEBHOOK_SECRET;
if (!SECRET) {
  console.error('WEBHOOK_SECRET env var is required');
  process.exit(1);
}

// Map GitHub repo full_name → deploy.sh project name
// Only repos listed here can trigger builds
const REPO_MAP = {
  'VisarDomi/life-document-organizer': 'lifevault',
  'VisarDomi/ordretten': 'ordretten',
  'VisarDomi/roni-application-tracker': 'roni',
  'VisarDomi/ura': 'ura',
  'VisarDomi/trader-ui': 'trader-ui',
  'VisarDomi/trader-svelte': ['tendies', 'tendies-showcase'],
  'VisarDomi/visar-dev-site': 'visar',
  'VisarDomi/biomorph-website': 'biomorph',
  'VisarDomi/cashback': ['cashback', 'cashback-deck', 'cashback-biz', 'cashback-v2', 'cashback-v3'],
  'VisarDomi/visar-blog': 'blog',
  'VisarDomi/visar-job-search': 'research-visar',
  'VisarDomi/hetzner-infra': ['admin', 'pm-graph'],
  'ErdalDomi/argus': 'argus',
  // 'ErdalDomi/life-document-organizer': 'lifevault',
  // etc.
};

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  try { appendFileSync(LOG_FILE, line + '\n'); } catch {}
}

function verifySignature(payload, signature) {
  if (!signature) return false;
  const expected = 'sha256=' + createHmac('sha256', SECRET).update(payload).digest('hex');
  if (expected.length !== signature.length) return false;
  return timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
}

function triggerDeploy(project) {
  log(`Triggering deploy for: ${project}`);
  const child = spawn(DEPLOY_SCRIPT, [project], {
    stdio: ['ignore', 'pipe', 'pipe'],
    detached: true,
  });
  child.stdout.on('data', (d) => log(`[${project}] ${d.toString().trim()}`));
  child.stderr.on('data', (d) => log(`[${project}] ERR: ${d.toString().trim()}`));
  child.on('close', (code) => log(`[${project}] deploy exited with code ${code}`));
  child.unref();
}

const server = createServer((req, res) => {
  if (req.method !== 'POST' || req.url !== '/webhook') {
    res.writeHead(404);
    res.end('not found');
    return;
  }

  const chunks = [];
  req.on('data', (chunk) => chunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const signature = req.headers['x-hub-signature-256'];

    if (!verifySignature(body, signature)) {
      log('Rejected: invalid signature');
      res.writeHead(403);
      res.end('invalid signature');
      return;
    }

    const event = req.headers['x-github-event'];
    if (event !== 'push') {
      log(`Ignored event: ${event}`);
      res.writeHead(200);
      res.end('ignored');
      return;
    }

    let payload;
    try {
      payload = JSON.parse(body.toString());
    } catch {
      res.writeHead(400);
      res.end('invalid json');
      return;
    }

    // Only deploy on push to main/master
    const ref = payload.ref || '';
    if (ref !== 'refs/heads/main' && ref !== 'refs/heads/master') {
      log(`Ignored push to ${ref}`);
      res.writeHead(200);
      res.end('ignored branch');
      return;
    }

    const repoName = payload.repository?.full_name;
    const projects = REPO_MAP[repoName];
    if (!projects) {
      log(`Unknown repo: ${repoName}`);
      res.writeHead(200);
      res.end('unknown repo');
      return;
    }

    // Handle single project or array of projects (monorepos like cashback)
    const projectList = Array.isArray(projects) ? projects : [projects];
    for (const project of projectList) {
      triggerDeploy(project);
    }

    log(`Accepted push to ${repoName} (${ref}) → deploying: ${projectList.join(', ')}`);
    res.writeHead(200);
    res.end('ok');
  });
});

server.listen(PORT, '127.0.0.1', () => {
  log(`Webhook server listening on 127.0.0.1:${PORT}`);
});
