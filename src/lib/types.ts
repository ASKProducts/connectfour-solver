/*
 * connectfour-solver TypeScript types
 * Copyright (C) 2024 ASKProducts
 *
 * AGPL-3.0-or-later — see LICENSE
 * Based on Connect4 Game Solver by Pascal Pons <http://connect4.gamesolver.org>
 */

export interface SolverModule {
  _solver_init(): void;
  _solver_load_book(dataPtr: number, length: number): number;
  _solver_solve(posPtr: number, weak: number): number;
  _solver_analyze(posPtr: number, weak: number, scoresPtr: number): number;
  _solver_reset(): void;
  _solver_get_node_count(): number;
  _malloc(size: number): number;
  _free(ptr: number): void;
  HEAPU8: Uint8Array;
  HEAP32: Int32Array;
  stringToUTF8(str: string, outPtr: number, maxBytesToWrite: number): void;
  UTF8ToString(ptr: number): string;
}

export type SolverModuleFactory = (options?: {
  wasmBinary?: ArrayBuffer;
  locateFile?: (path: string, prefix: string) => string;
}) => Promise<SolverModule>;
