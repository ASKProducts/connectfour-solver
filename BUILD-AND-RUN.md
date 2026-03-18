# Building and Running the Solver

## Prerequisites

- g++ with C++11 support
- macOS or Linux

## Build

```bash
cd pascal-pons-solver
make c4solver      # Build the solver binary
make generator     # Build the opening book generator (optional)
make clean         # Remove build artifacts
```

Compiler flags: `-std=c++11 -W -Wall -O3 -DNDEBUG`

## Running the Solver

The solver reads positions from stdin (one per line) and outputs scores to stdout.

### Input Format

Move sequences as digit strings. Columns are **1-indexed** (1-7, left to right).
Example: `"4453"` means P1 plays col 4, P2 plays col 4, P1 plays col 5, P2 plays col 3.

**Important**: The solver rejects positions where:
- A winning alignment already exists (it only solves non-terminal positions)
- A column is full
- Invalid characters appear

### Output Format

```
<position> <score>              # default mode
<position> <s1> <s2> ... <s7>   # with -a flag (analyze mode)
```

### Score Interpretation

- **Positive score N**: Current player wins. N = (42+1 - total_moves) / 2 gives how many moves before win. Higher = faster win.
- **Negative score -N**: Current player loses. Lower = faster loss.
- **Zero**: Draw with best play.
- **100** (in analyze mode): Column is full / illegal move.
- Score range: -21 to +21 for standard 7x6 board.

### CLI Options

| Flag | Description |
|------|-------------|
| `-a` | Analyze mode: output score for each of the 7 columns |
| `-w` | Weak solver: only returns -1, 0, or +1 (faster) |
| `-b <file>` | Custom opening book file (default: `7x6.book`) |

### Examples

```bash
# Score a single position
echo "4453" | ./c4solver
# Output: 4453 -5

# Analyze all moves for a position
echo "4453" | ./c4solver -a
# Output: 4453 -5 -5 -2 -3 -4 -2 -2

# Weak solve (just win/loss/draw)
echo "4453" | ./c4solver -w
# Output: 4453 -1

# Multiple positions
printf "4453\n445362\n" | ./c4solver -a
```

## Opening Book

The solver looks for `7x6.book` in the current directory. Without it:
- Solving deep positions (< ~12 moves played) is very slow
- Mid-game positions (12+ moves) solve quickly
- Warning printed to stderr: `Unable to load opening book: 7x6.book`

### Generating an Opening Book

1. Generate positions to solve:
   ```bash
   ./generator 14 > positions.txt
   ```
2. Solve them (this takes a very long time):
   ```bash
   ./c4solver < positions.txt > scored.txt
   ```
3. Create the book:
   ```bash
   ./generator < scored.txt
   ```
   This produces `7x6.book`.

**Note**: Generating a full opening book is computationally expensive. The online solver at connect4.gamesolver.org uses a pre-computed book that is not available for download.

## Performance Notes (without opening book)

| Position depth | Approximate solve time |
|----------------|----------------------|
| 0 moves (empty board) | Very slow (minutes+) |
| 4 moves | Seconds |
| 8+ moves | Sub-second |
| 12+ moves | Milliseconds |
| 20+ moves | Microseconds |

The opening book primarily helps with positions in the first ~14 moves.
