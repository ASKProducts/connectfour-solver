/*
 * connectfour-solver — WASM-based Connect Four solver for Node.js
 * Copyright (C) 2024 ASKProducts
 *
 * AGPL-3.0-or-later — see LICENSE
 * Based on Connect4 Game Solver by Pascal Pons <http://connect4.gamesolver.org>
 */

import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import type { SolverModule, SolverModuleFactory } from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const WASM_DIR = resolve(__dirname, '..', 'wasm');
const WIDTH = 7;

export interface SolverOptions {
  bookPath?: string;
  weak?: boolean;
}

export interface Solver {
  solve(position: string | number[]): number;
  analyze(position: string | number[]): number[];
  reset(): void;
  readonly bookLoaded: boolean;
}

// Singleton: only one WASM instance per process
let instancePromise: Promise<Solver> | null = null;

function normalizePosition(position: string | number[]): string {
  if (typeof position === 'string') return position;
  // number[] is 0-indexed columns, convert to 1-indexed string
  return position.map(c => String(c + 1)).join('');
}

function findBookPath(explicit?: string): string | null {
  if (explicit) {
    if (existsSync(explicit)) return explicit;
    return null;
  }

  // Search order: node_modules cache → cwd
  const candidates = [
    resolve(process.cwd(), 'node_modules', '.cache', 'connectfour-solver', '7x6.book'),
    resolve(process.cwd(), '7x6.book'),
  ];

  for (const p of candidates) {
    if (existsSync(p)) return p;
  }
  return null;
}

async function initSolver(options?: SolverOptions): Promise<Solver> {
  // Load the Emscripten module factory
  const modulePath = join(WASM_DIR, 'solver.cjs');
  const wasmPath = join(WASM_DIR, 'solver.wasm');

  // Read WASM binary so we control the path
  const wasmBinary = await readFile(wasmPath);

  // Import the Emscripten factory (CommonJS module)
  const require = createRequire(import.meta.url);
  const createSolverModule: SolverModuleFactory = require(modulePath);

  const module: SolverModule = await createSolverModule({
    wasmBinary: wasmBinary.buffer.slice(
      wasmBinary.byteOffset,
      wasmBinary.byteOffset + wasmBinary.byteLength
    ),
  });

  // Initialize solver
  module._solver_init();

  // Try to load opening book
  let _bookLoaded = false;
  const bookPath = findBookPath(options?.bookPath);
  if (bookPath) {
    try {
      const bookData = await readFile(bookPath);
      const bookPtr = module._malloc(bookData.length);
      module.HEAPU8.set(bookData, bookPtr);
      const result = module._solver_load_book(bookPtr, bookData.length);
      module._free(bookPtr);
      _bookLoaded = result === 1;
      if (_bookLoaded) {
        console.error(`Loaded opening book: ${bookPath} (${(bookData.length / 1024 / 1024).toFixed(1)}MB)`);
      }
    } catch (err) {
      console.error(`Warning: failed to load opening book from ${bookPath}:`, err);
    }
  } else {
    console.error('Warning: no opening book found. Solver will work but early positions will be slow.');
  }

  const weak = options?.weak ?? false;

  // Allocate persistent buffer for analyze scores (7 ints = 28 bytes)
  const scoresPtr = module._malloc(WIDTH * 4);

  return {
    solve(position: string | number[]): number {
      const posStr = normalizePosition(position);
      const posBytes = new TextEncoder().encode(posStr + '\0');
      const posPtr = module._malloc(posBytes.length);
      module.HEAPU8.set(posBytes, posPtr);
      const result = module._solver_solve(posPtr, weak ? 1 : 0);
      module._free(posPtr);
      return result;
    },

    analyze(position: string | number[]): number[] {
      const posStr = normalizePosition(position);
      const posBytes = new TextEncoder().encode(posStr + '\0');
      const posPtr = module._malloc(posBytes.length);
      module.HEAPU8.set(posBytes, posPtr);
      const rc = module._solver_analyze(posPtr, weak ? 1 : 0, scoresPtr);
      module._free(posPtr);

      if (rc !== 0) {
        throw new Error(`Invalid position: ${posStr}`);
      }

      const scores: number[] = [];
      for (let i = 0; i < WIDTH; i++) {
        const score = module.HEAP32[(scoresPtr >> 2) + i];
        // Map INVALID_MOVE (-1000) to 100 for full/illegal columns
        scores.push(score === -1000 ? 100 : score);
      }
      return scores;
    },

    reset(): void {
      module._solver_reset();
    },

    get bookLoaded(): boolean {
      return _bookLoaded;
    },
  };
}

export async function createSolver(options?: SolverOptions): Promise<Solver> {
  if (!instancePromise) {
    instancePromise = initSolver(options);
  }
  return instancePromise;
}
