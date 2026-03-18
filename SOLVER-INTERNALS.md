# Solver Internals

How Pascal Pons' Connect Four solver works, distilled from the source code and blog tutorial.

## Architecture Overview

```
Input (move string "4453")
  → Position (bitboard representation)
    → Solver.solve()
      → Iterative deepening with null-window search
        → negamax() with alpha-beta pruning
          → Transposition table (memoization)
          → Opening book (pre-computed early positions)
          → Move ordering (best-first via MoveSorter)
  → Output (score integer)
```

## 1. Board Representation (Position.hpp)

### Bitboard Encoding

Two 64-bit integers represent the entire board:
- `current_position`: 1 = current player's stone, 0 = everything else
- `mask`: 1 = any stone (either player), 0 = empty

Board layout (bit indices for 7x6):
```
 5 12 19 26 33 40 47   ← sentinel row (overflow detection)
 4 11 18 25 32 39 46   ← row 5 (top)
 3 10 17 24 31 38 45
 2  9 16 23 30 37 44
 1  8 15 22 29 36 43
 0  7 14 21 28 35 42   ← row 0 (bottom)
```

Each column uses HEIGHT+1 = 7 bits (extra sentinel bit at top for overflow).

### Key Operations

**Play a move** (column col):
```cpp
current_position ^= mask;                        // swap current/opponent
mask |= mask + bottom_mask_col(col);             // set new stone bit
moves++;
```

**Win detection** — bitwise shift-and-AND in 4 directions:
```cpp
// Horizontal: shift by HEIGHT+1 (7) to move between columns
m = pos & (pos >> 7); if (m & (m >> 14)) → win

// Vertical: shift by 1 within column
m = pos & (pos >> 1); if (m & (m >> 2)) → win

// Diagonal: shift by HEIGHT (6) or HEIGHT+2 (8)
```

**Unique key** = `position + mask + bottom` — unambiguous board encoding used for transposition table lookups.

**Symmetric key** (`key3()`): base-3 encoding that returns the minimum of left-to-right and right-to-left readings. Used for opening book to avoid storing mirror positions.

## 2. Core Search (Solver.cpp)

### Negamax with Alpha-Beta Pruning

The negamax variant simplifies minimax by always evaluating from the current player's perspective. The score is negated when passing to the opponent.

```
negamax(position, alpha, beta):
  if no non-losing moves → return loss score
  if board nearly full → return 0 (draw)

  check transposition table → refine alpha/beta
  check opening book → return if found

  for each move (ordered by heuristic score):
    score = -negamax(child, -beta, -alpha)
    if score >= beta → prune (cutoff)
    if score > alpha → alpha = score

  store alpha in transposition table
  return alpha
```

### Iterative Deepening with Null Windows

Instead of a single wide-window search, the solver binary-searches for the exact score:

```
min = worst possible score
max = best possible score

while min < max:
  med = midpoint(min, max)
  result = negamax(position, med, med+1)   // null window
  if result <= med: max = result
  else: min = result

return min  // exact score
```

This converges quickly because each null-window search is fast (tight pruning).

### Move Ordering

Critical for alpha-beta efficiency. Moves explored in this order:
1. **Winning moves** checked first (immediate return)
2. **Forced moves** — if opponent has a winning threat, must block
3. **Center-first heuristic** — column order: 4, 5, 3, 6, 2, 7, 1 (1-indexed)
4. **Score-based sorting** — `moveScore()` counts how many winning spots a move creates, sorted descending via MoveSorter

### Losing Move Anticipation

Before searching, `possibleNonLosingMoves()` filters out moves that:
- Leave the opponent with an immediate win
- Play directly below an opponent's winning spot

If the opponent has 2+ winning threats simultaneously → position is lost.

## 3. Transposition Table (TranspositionTable.hpp)

### Structure

Fixed-size hash table with simple replacement policy (no chaining).

- Size: prime number near 2^24 (~16M entries)
- Key: truncated position key (uint32_t typically)
- Value: uint8_t encoding score bounds
- Index: `key % table_size`

### Score Encoding

Values stored as offsets from MIN_SCORE:
- Values 1 to (MAX_SCORE - MIN_SCORE + 1): **upper bound** of score
- Values > (MAX_SCORE - MIN_SCORE + 1): **lower bound** of score
- Value 0: empty (no data)

This allows storing both upper and lower bounds in a single uint8_t.

### Why Prime Size?

The table size is a prime number so that `key % size` distributes keys uniformly regardless of key bit patterns. Computed at compile time via constexpr.

## 4. Opening Book (OpeningBook.hpp)

### Purpose

Pre-computed scores for positions in the first ~14 moves. Without it, early positions are extremely expensive to solve.

### File Format

Binary file with header:
```
Byte 0: width (7)
Byte 1: height (6)
Byte 2: max depth (14)
Byte 3: partial key size (1/2/4/8 bytes)
Byte 4: value size (1 byte)
Byte 5: log2(table size)
Byte 6+: key array, then value array
```

### Lookup

Uses `key3()` (symmetric key) so mirror positions share entries. Only consulted for positions with `nbMoves() <= depth`.

## 5. Score System

Score represents distance to game end:
- **+N**: Current player wins in N moves before board fills
- **-N**: Current player loses in N moves before board fills
- **0**: Draw with perfect play

Formula: `score = (WIDTH*HEIGHT + 1 - nbMoves) / 2` for an immediate win.

For a 7x6 board:
- Maximum score: +21 (win on move 1, but impossible in practice)
- Minimum score: -21
- Realistic max: +18 (win on move 7, earliest possible 4-in-a-row)

## 6. Key Optimizations Summary

| Optimization | Blog Part | Speedup |
|-------------|-----------|---------|
| Alpha-beta pruning | 4 | ~100x over minimax |
| Center-first move ordering | 5 | ~5-10x |
| Bitboard representation | 6 | ~5x (fast win detection) |
| Transposition table | 7 | ~10-100x (avoids recomputation) |
| Iterative deepening + null windows | 8 | ~2-5x |
| Losing move anticipation | 9 | ~2-5x |
| Score-based move ordering | 10 | ~2-3x |
| Optimized TT (Chinese remainder) | 11 | Memory savings |
| Lower bound in TT | 12 | ~1.5-2x |
| Opening book | (code) | Massive for early positions |
