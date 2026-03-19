#!/usr/bin/env bash
#
# make-books.sh — Generate shrunk opening books at depths 8, 10, 12 from scored layer data
#
# Compiles a depth-specific generator for each target, concatenates the appropriate
# layer scored.txt files, and pipes them through to produce the book.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$SCRIPT_DIR/book-generation"

# Depth → log_size mapping
# log_size must be in range 21-27 (OpeningBook constraint)
# depth 8:  ~130K positions, log_size=21 (2M slots, plenty of room)  → ~4MB
# depth 10: ~1.2M positions, log_size=21 (2M slots, good coverage)   → ~4MB
# depth 12: ~9.2M positions, log_size=23 (8.4M slots, similar to d14) → ~16MB
# depth 14: existing 7x6.book (log_size=23)                          → ~24MB

get_log_size() {
    # Lossy hash table — shallow positions written last survive collisions
    # Same approach as depth-14 (log_size=23 for 58M positions)
    case "$1" in
        6)  echo 21 ;;  # 11K positions in 2.1M slots — lossless
        8)  echo 21 ;;  # 130K positions in 2.1M slots — lossless
        10) echo 21 ;;  # 1.2M positions in 2.1M slots — slightly lossy
        12) echo 23 ;;  # 9.2M positions in 8.4M slots — lossy like depth-14
    esac
}

for TARGET_DEPTH in 6 8 10 12; do
    LOG_SIZE=$(get_log_size $TARGET_DEPTH)
    OUTPUT="$SCRIPT_DIR/7x6-depth${TARGET_DEPTH}.book"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Building depth-${TARGET_DEPTH} book (log_size=${LOG_SIZE})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Compile generator with this depth's constants
    GENERATOR_SRC=$(mktemp /tmp/generator_d${TARGET_DEPTH}_XXXX.cpp)
    cat > "$GENERATOR_SRC" << CPPEOF
#include "Position.hpp"
#include "OpeningBook.hpp"
#include <iostream>
#include <sstream>
#include <string>

using namespace GameSolver::Connect4;

int main() {
    static constexpr int BOOK_SIZE = ${LOG_SIZE};
    static constexpr int DEPTH = ${TARGET_DEPTH};
    static constexpr double LOG_3 = 1.58496250072;
    TranspositionTable<uint_t<int((DEPTH + Position::WIDTH -1) * LOG_3) + 1 - BOOK_SIZE>, Position::position_t, uint8_t, BOOK_SIZE> *table =
        new TranspositionTable<uint_t<int((DEPTH + Position::WIDTH -1) * LOG_3) + 1 - BOOK_SIZE>, Position::position_t, uint8_t, BOOK_SIZE>();

    long long count = 0;
    for(std::string line; getline(std::cin, line); count++) {
        if(line.length() == 0) break;
        std::istringstream iss(line);
        std::string pos;
        getline(iss, pos, ' ');
        int score;
        iss >> score;

        Position P;
        if(iss.fail() || !iss.eof()
            || P.play(pos) != pos.length()
            || score < Position::MIN_SCORE || score > Position::MAX_SCORE) {
            std::cerr << "Invalid line (ignored): " << line << std::endl;
            continue;
        }
        table->put(P.key3(), score - Position::MIN_SCORE + 1);
        if(count % 1000000 == 0 && count > 0) std::cerr << count << " positions processed" << std::endl;
    }
    std::cerr << count << " total positions processed" << std::endl;

    OpeningBook book{Position::WIDTH, Position::HEIGHT, DEPTH, table};
    book.save("${OUTPUT}");
    return 0;
}
CPPEOF

    GENERATOR_BIN="/tmp/generator_d${TARGET_DEPTH}"
    echo "Compiling generator for depth ${TARGET_DEPTH}..."
    g++ --std=c++11 -W -Wall -O3 -DNDEBUG -I"$SCRIPT_DIR" -o "$GENERATOR_BIN" "$GENERATOR_SRC"
    rm "$GENERATOR_SRC"

    # Concatenate scored data deepest-first so shallow positions are written last
    # (shallow positions survive hash collisions — they're most important)
    echo "Combining scored data from layers ${TARGET_DEPTH}-0 (deepest first)..."
    TOTAL=0
    LAYER_FILES=""
    for LAYER_DEPTH in 14 12 10 8 6 4 2 0; do
        if [ "$LAYER_DEPTH" -gt "$TARGET_DEPTH" ]; then
            continue
        fi
        SCORED="$WORK_DIR/layer_$LAYER_DEPTH/scored.txt"
        if [ -f "$SCORED" ]; then
            COUNT=$(wc -l < "$SCORED" | tr -d ' ')
            TOTAL=$((TOTAL + COUNT))
            LAYER_FILES="$LAYER_FILES $SCORED"
            echo "  layer $LAYER_DEPTH: $COUNT positions"
        fi
    done
    echo "  total: $TOTAL positions"

    echo "Generating book..."
    cat $LAYER_FILES | "$GENERATOR_BIN"

    SIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')
    echo "✓ Created $OUTPUT ($SIZE)"
    rm "$GENERATOR_BIN"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All books:"
ls -lh "$SCRIPT_DIR"/7x6*.book
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
