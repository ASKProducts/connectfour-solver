# connectfour-solver

A WASM-based Connect Four perfect solver for Node.js. Compiles the [Pascal Pons Connect Four solver](http://connect4.gamesolver.org) to WebAssembly via Emscripten for server-side use.

## Attribution

This package is based on the **Connect Four solver by [Pascal Pons](http://connect4.gamesolver.org)**. The original solver implements a highly optimized alpha-beta search with:

- Bitboard position representation
- Transposition table with Zobrist hashing
- Opening book for early positions
- Iterative deepening with alpha-beta narrowing

The original solver source, tutorial, and documentation are available at:
- **Solver**: [connect4.gamesolver.org](http://connect4.gamesolver.org)
- **Tutorial**: [blog.gamesolver.org](http://blog.gamesolver.org)

## Installation

```bash
npm install connectfour-solver
```

### Opening Book

The solver **requires** an opening book. Install it after `npm install`:

```bash
npx connectfour-solver install-book
```

By default this downloads the Pascal Pons original full book (32MB, recommended). Smaller books are available:

```bash
npx connectfour-solver install-book --list
npx connectfour-solver install-book --depth 10
```

| Depth | Positions | Size | Coverage |
|-------|-----------|------|----------|
| 6 | ~11K | 4MB | Positions ≤6 moves |
| 8 | ~130K | 4MB | Positions ≤8 moves |
| 10 | ~1.2M | 4MB | Positions ≤10 moves |
| 12 | ~9.2M | 16MB | Positions ≤12 moves |
| 14 | ~58M | 24MB | Positions ≤14 moves |
| full | ~58M | 32MB | Pascal Pons original (fewer hash collisions, recommended) |

## Usage

```typescript
import { createSolver } from 'connectfour-solver';

const solver = await createSolver();

// Solve a position (returns score for current player)
solver.solve('4453');           // => -2
solver.solve([3, 3, 4, 2]);    // => -2 (0-indexed columns)

// Analyze all possible moves (returns score for each column)
solver.analyze('4453');         // => [-5, -5, -2, -3, -4, -2, -2]
solver.analyze([3, 3, 4, 2]);  // => [-5, -5, -2, -3, -4, -2, -2]

// 100 = column is full/illegal
solver.analyze('');             // => [-2, -1, 0, 1, 0, -1, -2]

solver.bookLoaded;              // => true
solver.reset();                 // clear transposition table
```

### Position Format

- **String**: 1-indexed column digits, e.g. `'4453'` means columns 4, 4, 5, 3
- **Array**: 0-indexed column numbers, e.g. `[3, 3, 4, 2]` (same position)

### Scores

- **Positive**: current player wins (higher = faster win)
- **Negative**: current player loses (lower = faster loss)
- **Zero**: draw with perfect play
- **100**: column is full or illegal

### Singleton Pattern

`createSolver()` returns the same WASM instance on subsequent calls. This is designed for serverless environments (e.g. Vercel) where the transposition table stays warm across requests.

### Explicit Book Path

```typescript
const solver = await createSolver({ bookPath: '/path/to/7x6.book' });
```

Book discovery order: explicit `bookPath` > `node_modules/.cache/connectfour-solver/7x6.book` > `./7x6.book` > no book (with warning).

## Building from Source

### Prerequisites

- [Emscripten](https://emscripten.org/docs/getting_started/downloads.html) (`emcc` on PATH)
- Node.js >= 18
- TypeScript

### Build

```bash
npm install
npm run build:wasm    # Compile C++ to WASM
npm run build:ts      # Compile TypeScript
npm run build         # Both
```

## License

This package is licensed under the **GNU Affero General Public License v3.0** (AGPL-3.0-or-later), the same license as the original Pascal Pons solver.

See [LICENSE](LICENSE) for the full license text.

### What this means

- You can use this package freely in your projects
- If you modify this package and make it available over a network, you must make your modified source code available under AGPL-3.0
- Applications that use this package as a dependency (without modification) are not required to be AGPL-licensed
