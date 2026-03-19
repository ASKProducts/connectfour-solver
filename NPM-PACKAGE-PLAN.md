# `connectfour-solver` npm Package

## Context

Replace the external HTTP solver API (`connect4.gamesolver.org`) with a self-contained WASM-based npm package. The Pascal Pons C++ solver is compiled to WebAssembly via Emscripten and runs server-side in Vercel serverless functions. The opening book (~24MB) is NOT bundled with the package — it's installed separately via `npx connectfour-solver install-book`, which downloads from GitHub Releases.

## License

The Pascal Pons solver is **AGPL v3**. The `connectfour-solver` npm package must be published under AGPL v3 with source available on GitHub (`ASKProducts/connectfour-solver`). The web app (`connectfour-new-opus`) treats it as a separate package/aggregate.

## Package API

```typescript
import { createSolver } from 'connectfour-solver'

const solver = await createSolver()                    // loads WASM, auto-discovers book
const solver2 = await createSolver({ bookPath: '...' }) // explicit book path

solver.solve('4453')           // => -5
solver.solve([3, 3, 4, 2])    // => -5  (accepts 0-indexed array too)
solver.analyze('4453')         // => [-5, -5, -2, -3, -4, -2, -2]
solver.analyze([3, 3, 4, 2])  // => [-5, -5, -2, -3, -4, -2, -2]
solver.bookLoaded              // => true
solver.reset()                 // clear transposition table
```

Singleton pattern: only one WASM instance per process. Subsequent `createSolver()` calls return the same instance. This is critical for Vercel warm instances — the transposition table stays warm across requests.

## CLI

```
$ npx connectfour-solver install-book
# Defaults to depth 14 (full book)

$ npx connectfour-solver install-book --depth 10
# Install a smaller book (depth 10)

$ npx connectfour-solver install-book --list
# Show available books:
#   Depth   Positions    Size    Early-game coverage
#   ────────────────────────────────────────────────
#   8       ~118K        <1MB    Positions ≤8 moves
#   10      ~1.2M        ~2MB    Positions ≤10 moves
#   12      ~9.2M        ~12MB   Positions ≤12 moves
#   14      ~49M         ~24MB   Positions ≤14 moves (full)

Downloading 7x6-depth14.book from GitHub...
✓ Installed to node_modules/.cache/connectfour-solver/7x6.book (24MB)
```

Book discovery order: explicit `bookPath` option → `node_modules/.cache/connectfour-solver/7x6.book` → `process.cwd()/7x6.book` → warn and continue without book.

## Plan

### 1. C wrapper for Emscripten

**Create**: `src/wasm/solver-wrapper.cpp`

Exposes C-linkage functions that Emscripten exports:

```cpp
extern "C" {
  void solver_init();
  int solver_load_book(const uint8_t* data, int length);
  int solver_solve(const char* pos_str, int weak);
  int solver_analyze(const char* pos_str, int weak, int* scores_out);
  void solver_reset();
  unsigned long long solver_get_node_count();
}
```

Manages a single static `Solver` instance. `solver_analyze` writes 7 scores into a pre-allocated WASM heap array. Maps `INVALID_MOVE` (-1000) to `100` for full/illegal columns.

### 2. Add `loadFromBuffer()` to OpeningBook

**Modify**: `pascal-pons-solver/OpeningBook.hpp`

Add method that reads the same binary format from a `uint8_t*` buffer instead of `ifstream`. Mirrors `load()` line-for-line but replaces `ifs.read()` with `memcpy()` + offset tracking. This is needed because WASM doesn't have filesystem access — the book bytes are passed from JS into WASM memory.

**Modify**: `pascal-pons-solver/Solver.hpp`

Add public `loadBookFromBuffer(const uint8_t* data, size_t length)` that delegates to `book.loadFromBuffer()`.

### 3. Emscripten build

**Create**: `build/Makefile.emscripten`

Key flags:
- `-O3 -flto -DNDEBUG` — full optimization
- `MODULARIZE=1`, `EXPORT_NAME='createSolverModule'` — factory function for Node.js
- `ENVIRONMENT='node'` — server-side only, no browser shims
- `FILESYSTEM=0` — no virtual FS needed
- `ALLOW_MEMORY_GROWTH=1`, `INITIAL_MEMORY=128MB`, `MAXIMUM_MEMORY=256MB` — fits ~104MB working set (32MB transposition table + 24MB book + overhead)
- `SINGLE_FILE=0` — .wasm as separate file for bundler compatibility
- Exports: `_solver_init`, `_solver_load_book`, `_solver_solve`, `_solver_analyze`, `_solver_reset`, `_solver_get_node_count`, `_malloc`, `_free`

Output: `dist/wasm/solver.js` + `dist/wasm/solver.wasm`

### 4. TypeScript API

**Create**: `src/lib/index.ts`

```typescript
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

export async function createSolver(options?: SolverOptions): Promise<Solver>;
```

Implementation:
- Loads WASM via Emscripten factory, resolves `.wasm` file relative to package `dist/wasm/`
- Singleton: module-level promise ensures only one WASM instance per process
- Input normalization: `number[]` (0-indexed) → 1-indexed string via `cols.map(c => String(c + 1)).join('')`
- Book loading: reads file with `fs.readFile()`, copies into WASM heap via `_malloc` + `HEAPU8.set()`, calls `_solver_load_book()`
- Output: `_solver_analyze` writes to HEAP32 array, JS reads 7 ints back

**Create**: `src/lib/types.ts` — WASM module type definitions

### 5. CLI

**Create**: `src/cli/index.ts`

- Arg-based interface (no interactive prompts):
  - `install-book` — download and install book (default depth 14)
  - `install-book --depth <8|10|12|14>` — specific depth
  - `install-book --list` — show available books with sizes
- Uses `fetch` (Node 18+) for downloads with progress bar
- Downloads from GitHub Releases: `https://github.com/ASKProducts/connectfour-solver/releases/download/v{version}/7x6-depth{depth}.book`
- Saves to `node_modules/.cache/connectfour-solver/7x6.book`
- Creates cache directory if needed
- Zero dependencies — uses `process.argv` for arg parsing

### 6. Package configuration

**Create**: `package.json`

```json
{
  "name": "connectfour-solver",
  "type": "module",
  "main": "dist/lib/index.js",
  "types": "dist/lib/index.d.ts",
  "bin": { "connectfour-solver": "dist/cli/index.js" },
  "files": ["dist/"],
  "engines": { "node": ">=18.0.0" },
  "scripts": {
    "build:wasm": "cd build && make -f Makefile.emscripten",
    "build:ts": "tsc",
    "build": "npm run build:wasm && npm run build:ts"
  }
}
```

Zero runtime dependencies. DevDependencies: `typescript`, `emscripten` (system install).

**Create**: `tsconfig.json` — target ES2022, ESNext modules, declaration output

### 7. Generate book files at each depth

Smaller books (depth 8/10/12) are derived from the depth-14 book — no need to re-solve positions.

**Create**: `tools/shrink-book.cpp`

A standalone C++ tool that:
1. Loads the full depth-14 book (reads the hash table into memory)
2. Enumerates all valid Connect Four positions up to the target depth (recursive DFS over all legal move sequences, skipping positions where the game is already won)
3. For each position, looks it up in the depth-14 hash table and copies the value into a new, smaller hash table (sized appropriately for the target depth's position count)
4. Writes the new book with the target depth in the header

Usage: `./shrink-book 7x6.book 10 7x6-depth10.book`

The enumeration is fast (~1.2M positions for depth 10, ~9.2M for depth 12) and the full book is already loaded. This is a one-time offline tool — run it locally, upload resulting `.book` files as GitHub Release assets.

### 8. Web app integration

**Modify**: `connectfour-new-opus/src/lib/game/solver-server.ts`

Replace HTTP fetch to external API with:

```typescript
import { createSolver } from 'connectfour-solver';

let solverPromise: Promise<Solver> | null = null;
function getSolver() {
  if (!solverPromise) solverPromise = createSolver();
  return solverPromise;
}

export async function fetchSolverScoresServer(moveHistory: number[]): Promise<number[]> {
  // ... existing cache checks (serverCache Map + DB gameStates) ...
  const solver = await getSolver();
  const scores = solver.analyze(moveHistory);
  // ... existing cache persistence ...
  return scores;
}
```

Remove: `SOLVER_BASE_URL`, rate limiting, external `fetch()`, mock solver.
Keep: `serverCache` Map, DB cache in `gameStates` table.

**Modify**: `connectfour-new-opus/vercel.json` — ensure 1024MB memory for API functions

**Modify**: `connectfour-new-opus/next.config.ts` — may need `outputFileTracingIncludes` to ensure `.wasm` file is bundled in serverless functions

## Files to Create/Modify

| File | Action | Location |
|------|--------|----------|
| `src/wasm/solver-wrapper.cpp` | **CREATE** | connectfour-solver |
| `src/lib/index.ts` | **CREATE** | connectfour-solver |
| `src/lib/types.ts` | **CREATE** | connectfour-solver |
| `src/cli/index.ts` | **CREATE** | connectfour-solver |
| `tools/shrink-book.cpp` | **CREATE** | connectfour-solver |
| `build/Makefile.emscripten` | **CREATE** | connectfour-solver |
| `package.json` | **CREATE** | connectfour-solver |
| `tsconfig.json` | **CREATE** | connectfour-solver |
| `pascal-pons-solver/OpeningBook.hpp` | MODIFY — add `loadFromBuffer()` | connectfour-solver |
| `pascal-pons-solver/Solver.hpp` | MODIFY — add `loadBookFromBuffer()` | connectfour-solver |
| `src/lib/game/solver-server.ts` | MODIFY — replace HTTP with WASM | connectfour-new-opus |
| `vercel.json` | MODIFY — memory config | connectfour-new-opus |
| `next.config.ts` | MODIFY — WASM file tracing | connectfour-new-opus |

## Memory Budget (Vercel serverless)

| Component | Size |
|-----------|------|
| Transposition table (log_size=24) | ~32MB |
| Opening book (depth-14) | ~24MB |
| WASM overhead + stack | ~10MB |
| Node.js + Next.js runtime | ~200MB |
| **Total** | **~266MB** |
| Vercel Pro limit | 1024MB |

## Performance Characteristics

- **Cold start**: ~200-500ms (WASM init + book load). Fluid Compute minimizes these.
- **Warm request with book**: <100ms for most positions
- **Warm request without book, ≥12 moves played**: <100ms
- **Warm request without book, <12 moves played**: seconds (rare in practice)
- **vs. current external API**: eliminates 300ms+ network latency + rate limiting

## Verification

1. Build WASM: `npm run build:wasm` produces `dist/wasm/solver.js` + `solver.wasm`
2. Unit test: solve known positions (`4453` → `-5`, empty board → `0`)
3. CLI test: `npx connectfour-solver install-book` downloads and saves book
4. Integration test: replace `solver-server.ts`, run `npm run test:e2e` (all 35 tests pass)
5. Vercel deploy: verify cold start < 1s, warm requests < 100ms
