#!/usr/bin/env node
/*
 * connectfour-solver CLI
 * Copyright (C) 2024 ASKProducts
 *
 * AGPL-3.0-or-later — see LICENSE
 * Based on Connect4 Game Solver by Pascal Pons <http://connect4.gamesolver.org>
 */

import { existsSync, mkdirSync, createWriteStream } from 'node:fs';
import { resolve } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));

interface BookInfo {
  depth: number;
  positions: string;
  size: string;
  coverage: string;
}

const BOOKS: BookInfo[] = [
  { depth: 6, positions: '~11K', size: '4MB', coverage: 'Positions ≤6 moves' },
  { depth: 8, positions: '~130K', size: '4MB', coverage: 'Positions ≤8 moves' },
  { depth: 10, positions: '~1.2M', size: '4MB', coverage: 'Positions ≤10 moves' },
  { depth: 12, positions: '~9.2M', size: '16MB', coverage: 'Positions ≤12 moves' },
  { depth: 14, positions: '~58M', size: '24MB', coverage: 'Positions ≤14 moves (full)' },
];

function getVersion(): string {
  try {
    const pkgPath = join(__dirname, '..', '..', 'package.json');
    const pkg = JSON.parse(require('node:fs').readFileSync(pkgPath, 'utf-8'));
    return pkg.version;
  } catch {
    return '1.0.0';
  }
}

function getCacheDir(): string {
  return resolve(process.cwd(), 'node_modules', '.cache', 'connectfour-solver');
}

function showList(): void {
  console.log('Available opening books:\n');
  console.log('  Depth   Positions    Size    Early-game coverage');
  console.log('  ────────────────────────────────────────────────');
  for (const b of BOOKS) {
    const depth = String(b.depth).padStart(4);
    const positions = b.positions.padStart(10);
    const size = b.size.padStart(6);
    console.log(`  ${depth}   ${positions}   ${size}    ${b.coverage}`);
  }
  console.log('');
}

async function installBook(depth: number): Promise<void> {
  const book = BOOKS.find(b => b.depth === depth);
  if (!book) {
    console.error(`Error: invalid depth ${depth}. Valid depths: ${BOOKS.map(b => b.depth).join(', ')}`);
    process.exit(1);
  }

  const version = getVersion();
  const url = `https://github.com/ASKProducts/connectfour-solver/releases/download/v${version}/7x6-depth${depth}.book`;
  const cacheDir = getCacheDir();
  const outPath = resolve(cacheDir, '7x6.book');

  console.log(`Downloading depth-${depth} opening book (${book.size})...`);
  console.log(`URL: ${url}`);

  const response = await fetch(url);
  if (!response.ok) {
    // Try without version prefix for flexibility
    const altUrl = `https://github.com/ASKProducts/connectfour-solver/releases/latest/download/7x6-depth${depth}.book`;
    console.log(`Primary URL failed (${response.status}), trying: ${altUrl}`);
    const altResponse = await fetch(altUrl);
    if (!altResponse.ok) {
      console.error(`Error: failed to download book (HTTP ${altResponse.status})`);
      process.exit(1);
    }
    await downloadToFile(altResponse, cacheDir, outPath);
    return;
  }

  await downloadToFile(response, cacheDir, outPath);
}

async function downloadToFile(response: Response, cacheDir: string, outPath: string): Promise<void> {
  // Create cache directory
  mkdirSync(cacheDir, { recursive: true });

  const totalBytes = Number(response.headers.get('content-length') || 0);
  const body = response.body;
  if (!body) {
    console.error('Error: empty response body');
    process.exit(1);
  }

  const reader = body.getReader();
  const fileStream = createWriteStream(outPath);
  let downloaded = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      fileStream.write(value);
      downloaded += value.length;

      if (totalBytes > 0) {
        const pct = ((downloaded / totalBytes) * 100).toFixed(0);
        const mb = (downloaded / 1024 / 1024).toFixed(1);
        process.stdout.write(`\r  ${mb}MB / ${(totalBytes / 1024 / 1024).toFixed(1)}MB (${pct}%)`);
      } else {
        const mb = (downloaded / 1024 / 1024).toFixed(1);
        process.stdout.write(`\r  ${mb}MB downloaded`);
      }
    }
  } finally {
    fileStream.end();
  }

  console.log('');
  const sizeMB = (downloaded / 1024 / 1024).toFixed(0);
  console.log(`✓ Installed to ${outPath} (${sizeMB}MB)`);
}

function showHelp(): void {
  console.log(`connectfour-solver — WASM Connect Four solver

Usage:
  connectfour-solver install-book             Install opening book (default: depth 14)
  connectfour-solver install-book --depth N   Install book at specific depth (6/8/10/12/14)
  connectfour-solver install-book --list      Show available books
  connectfour-solver --help                   Show this help
`);
}

// Main
const args = process.argv.slice(2);

if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
  showHelp();
  process.exit(0);
}

if (args[0] === 'install-book') {
  if (args.includes('--list')) {
    showList();
    process.exit(0);
  }

  let depth = 14;
  const depthIdx = args.indexOf('--depth');
  if (depthIdx !== -1 && args[depthIdx + 1]) {
    depth = parseInt(args[depthIdx + 1], 10);
  }

  installBook(depth).catch(err => {
    console.error('Error:', err.message);
    process.exit(1);
  });
} else {
  console.error(`Unknown command: ${args[0]}`);
  showHelp();
  process.exit(1);
}
