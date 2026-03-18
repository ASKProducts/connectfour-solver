# Connect Four Solver Project

## Goal

Build a local solver service that can replace the external solver API used by the Connect Four game app. The app currently calls an external solver for:
- Column scores (which move is best)
- Game analysis (batch analysis of all positions in a game)
- AI move selection (solver scores feed into difficulty-weighted move selection)

## Current Architecture (in the game app)

The game app (`connectfour-new-opus`) calls solver endpoints:
- `src/lib/game/solver.ts` — client-side solver calls with localStorage caching
- `src/lib/game/solver-server.ts` — server-side solver with in-memory cache
- `/api/v1/training/solve` — proxy route to external solver
- `/api/v1/training/analyze` — batch analysis endpoint

## This Repo Structure

```
connectfour-solver/
├── pascal-pons-solver/     # Cloned from github.com/PascalPons/connect4
│   ├── c4solver            # Built binary (CLI tool)
│   ├── Solver.cpp/hpp      # Core algorithm
│   ├── Position.hpp        # Bitboard representation
│   ├── TranspositionTable.hpp
│   ├── MoveSorter.hpp
│   ├── OpeningBook.hpp
│   ├── main.cpp            # CLI entry point
│   ├── generator.cpp       # Opening book generator
│   └── Makefile
├── OVERVIEW.md             # This file
├── SOLVER-INTERNALS.md     # How the solver algorithm works
├── BLOG-NOTES.md           # Notes from blog.gamesolver.org tutorial
└── BUILD-AND-RUN.md        # How to build, run, and test
```

## References

- **Solver repo**: https://github.com/PascalPons/connect4
- **Tutorial blog**: http://blog.gamesolver.org/
- **Online solver**: http://connect4.gamesolver.org
