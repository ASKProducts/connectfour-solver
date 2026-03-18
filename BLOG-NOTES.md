# Blog Tutorial Notes

Notes from http://blog.gamesolver.org/ — Pascal Pons' 12-part tutorial on building a Connect Four solver.

## Part 1 — Introduction

- Connect Four is **strongly solved**: first player wins with perfect play
- First solved by James D. Allen (Oct 1, 1988) and independently Victor Allis (Oct 16, 1988) using rule-based + knowledge database approaches
- Later brute-force solved with more compute. John Tromp solved 8x8 in 2015
- Tutorial builds solver incrementally from naive to optimized

## Part 2 — Test Protocol

- Positions notated as digit strings: "4453" = columns played in sequence (1-indexed)
- Score: positive = current player wins, negative = loses, 0 = draw
- Score magnitude = distance to end (higher absolute value = faster outcome)
- Test sets of positions at various depths to benchmark solver speed

## Part 3 — MinMax (Negamax)

- Basic recursive algorithm: try all moves, opponent plays optimally
- Negamax simplification: `score = -negamax(opponent_position)`
- Always evaluate from current player's perspective
- Check for draw (board full) and immediate win before recursing
- **Extremely slow** — explores entire game tree

## Part 4 — Alpha-Beta Pruning

- Add alpha (best guaranteed score) and beta (worst opponent will allow) bounds
- Skip branches that can't improve alpha or beat beta
- `if score >= beta → prune` (opponent won't allow this good a position)
- Upper bound optimization: can't score better than winning in fewest remaining moves
- ~100x speedup over plain minimax

## Part 5 — Move Exploration Order

- Alpha-beta works best when best moves are tried first
- Simple heuristic: explore center columns first (columns 4,5,3,6,2,7,1)
- Center control is strong in Connect Four
- Significant speedup with this simple change

## Part 6 — Bitboard Representation

- Encode board as two uint64_t: `current_position` and `mask`
- Each column uses 7 bits (6 rows + 1 sentinel)
- Win detection via bit shifts in 4 directions — O(1) per check
- Key encoding: `position + mask + bottom` gives unique compact key
- ~5x speedup from faster board operations

### Bit layout (7x6 board):
```
 5 12 19 26 33 40 47   ← sentinel bits
 4 11 18 25 32 39 46
 3 10 17 24 31 38 45
 2  9 16 23 30 37 44
 1  8 15 22 29 36 43
 0  7 14 21 28 35 42
```

### Win check (4 directions):
- Vertical: shift by 1
- Horizontal: shift by 7 (HEIGHT+1)
- Diagonal ↗: shift by 6 (HEIGHT)
- Diagonal ↘: shift by 8 (HEIGHT+2)

## Part 7 — Transposition Table

- Hash table mapping position keys to scores
- Avoids re-evaluating positions reached via different move orders
- Simple replacement policy (no chaining — newest overwrites)
- Stores **upper bounds** only initially
- Size should be prime for good hash distribution
- ~10-100x speedup depending on position

## Part 8 — Iterative Deepening & Null Windows

- Instead of one wide search, binary-search for exact score
- Use null-window (alpha, alpha+1) searches to test if score > threshold
- Converge to exact score by halving the range each iteration
- Each null-window search prunes heavily due to tight bounds
- Also supports **weak solver** mode: only determine -1/0/+1

## Part 9 — Anticipate Losing Moves

- Before exploring, filter out moves that lose immediately
- `possibleNonLosingMoves()`: exclude moves where opponent wins next turn
- Also avoid playing below opponent's winning spot
- If opponent has 2+ forced wins simultaneously → return loss immediately
- Uses `compute_winning_position()` — bitboard function that finds all winning spots

## Part 10 — Better Move Ordering

- Score each move by counting winning spots it creates (`moveScore()`)
- `popcount(compute_winning_position(position | move, mask))`
- Use `MoveSorter` (insertion sort, max 7 elements) to try highest-scoring moves first
- Better than center-first alone; combines both heuristics

## Part 11 — Optimized Transposition Table

- Use Chinese Remainder Theorem to store truncated keys
- Table size is prime, key type is smaller than full key
- `key % prime_size` for index, store truncated key for verification
- Saves memory → can fit more entries → fewer collisions → faster
- Compile-time prime computation via constexpr

## Part 12 — Lower Bound in Transposition Table

- Store both upper bounds AND lower bounds in the transposition table
- Encode in single uint8_t: values above threshold = lower bound, below = upper bound
- On lookup: if lower bound found → raise alpha; if upper bound → lower beta
- Prune if alpha >= beta after either adjustment
- ~1.5-2x additional speedup

## Key Takeaways

1. The solver is fast because of the **combination** of all optimizations, not any single one
2. **Opening book** is critical for early positions — without it, solving empty/near-empty boards is infeasible in real-time
3. The bitboard representation enables O(1) win detection and efficient move generation
4. Move ordering is the single most impactful optimization for alpha-beta
5. The solver outputs scores in a format where column 100 = illegal (full column)
