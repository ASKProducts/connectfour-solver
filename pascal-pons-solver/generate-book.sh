#!/bin/bash
#
# generate-book.sh — Layered opening book generation with resume support
#
# Solves positions bottom-up: depth 14 → 12 → 10 → ... → 0
# Each layer builds a book that accelerates solving the next (harder) layer.
#
# Usage:
#   ./generate-book.sh             # Run with 16 workers (default)
#   ./generate-book.sh 8           # Run with 8 workers
#   ./generate-book.sh status      # Show progress (top 10 chunks)
#   ./generate-book.sh status --all  # Show progress (all chunks)
#   ./generate-book.sh watch       # Live progress (refreshes every 5s)
#   ./generate-book.sh watch 2     # Live progress (refreshes every 2s)
#   ./generate-book.sh watch --all # Live progress showing all chunks
#
# Safe to interrupt (Ctrl+C / kill) and re-run — picks up where it left off.
#

# No set -e: we handle errors explicitly to avoid killing background workers

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$SCRIPT_DIR/book-generation"
SOLVER="$SCRIPT_DIR/c4solver"
GENERATOR="$SCRIPT_DIR/generator"
MAX_DEPTH=14
NUM_WORKERS="${1:-16}"

# Layers solved from easiest (deepest) to hardest (shallowest)
# Each layer includes positions of that depth and the one below it
# (even depths only since positions alternate players)
LAYERS=(14 12 10 8 6 4 2 0)

# ─── Helpers ──────────────────────────────────────────────────────────────────

current_layer() {
    # Find the first incomplete layer
    for depth in "${LAYERS[@]}"; do
        local layer_dir="$WORK_DIR/layer_$depth"
        if [ ! -f "$layer_dir/.done" ]; then
            echo "$depth"
            return
        fi
    done
    echo "done"
}

positions_for_layer() {
    # Extract positions of a given depth (by string length) from positions file
    local depth="$1"
    local outfile="$2"
    # Depth 0 = empty string (length 0), depth N = length N
    # Include both this depth and one below (odd depth positions)
    if [ "$depth" -eq 0 ]; then
        awk 'length == 0 || length == 1' "$WORK_DIR/positions.txt" > "$outfile"
    else
        local prev=$((depth - 1))
        awk -v d="$depth" -v p="$prev" 'length == d || length == p' "$WORK_DIR/positions.txt" > "$outfile"
    fi
}

build_book_from_scored() {
    # Combine all scored files from completed layers + current progress into a book
    local book_input="$WORK_DIR/book_input.txt"
    > "$book_input"  # empty it

    # Add all completed layers
    for depth in "${LAYERS[@]}"; do
        local scored="$WORK_DIR/layer_$depth/scored.txt"
        if [ -f "$scored" ]; then
            cat "$scored" >> "$book_input"
        fi
    done

    local count=$(wc -l < "$book_input" | tr -d ' ')
    if [ "$count" -eq 0 ]; then
        return 1
    fi

    echo "[$(date '+%H:%M:%S')] Building book from $count scored positions..."
    cd "$SCRIPT_DIR"
    "$GENERATOR" < "$book_input"
    echo "[$(date '+%H:%M:%S')] Book built: $(ls -lh 7x6.book | awk '{print $5}')"
}

# ─── Status command ───────────────────────────────────────────────────────────

show_status() {
    if [ ! -d "$WORK_DIR" ] || [ ! -f "$WORK_DIR/positions.txt" ]; then
        echo "No generation in progress. Run ./generate-book.sh to start."
        return 1
    fi

    local grand_total=0
    local grand_solved=0
    local cur_layer=$(current_layer)

    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║          Opening Book Generation — Layered Approach         ║"
    echo "  ╠══════════════════════════════════════════════════════════════╣"
    echo ""
    echo "  Layer   Positions    Solved       %     Status"
    echo "  ─────   ─────────    ─────────    ───   ──────"

    for depth in "${LAYERS[@]}"; do
        local layer_dir="$WORK_DIR/layer_$depth"
        local positions_file="$layer_dir/positions.txt"
        local layer_total=0
        local layer_solved=0
        local status="·"

        if [ -f "$positions_file" ]; then
            layer_total=$(wc -l < "$positions_file" | tr -d ' ')
        elif [ -f "$WORK_DIR/layer_counts.txt" ]; then
            layer_total=$(grep "^$depth " "$WORK_DIR/layer_counts.txt" | awk '{print $2}')
            layer_total="${layer_total:-0}"
        fi

        if [ -f "$layer_dir/.done" ]; then
            layer_solved="$layer_total"
            status="✓"
        elif [ -d "$layer_dir/chunks" ]; then
            # Count output lines per chunk (no overlap possible — exclusive ownership)
            for chunk_input in "$layer_dir/chunks"/input_*; do
                [ -f "$chunk_input" ] || continue
                local cid=$(basename "$chunk_input" | sed 's/input_//')
                if [ -f "$layer_dir/chunks/output_$cid" ]; then
                    local chunk_solved=$(wc -l < "$layer_dir/chunks/output_$cid" | tr -d ' ')
                    layer_solved=$((layer_solved + chunk_solved))
                fi
            done
            if [ "$depth" = "$cur_layer" ]; then
                # Layer-specific ETA
                local layer_snap="$layer_dir/.layer_snap"
                local layer_remaining=$((layer_total - layer_solved))
                local now=$(date +%s)
                local layer_eta=""
                if [ -f "$layer_snap" ]; then
                    local lp_solved lp_time lp_eta
                    lp_solved=$(awk '{print $1}' "$layer_snap")
                    lp_time=$(awk '{print $2}' "$layer_snap")
                    lp_eta=$(awk '{$1=$2=""; print substr($0,3)}' "$layer_snap")
                    local ldt=$((now - lp_time))
                    local ldc=$((layer_solved - lp_solved))
                    if [ "$ldt" -ge 3 ]; then
                        if [ "$ldc" -gt 0 ]; then
                            local lrate=$(echo "scale=2; $ldc / $ldt" | bc 2>/dev/null || echo "0")
                            local leta=$(echo "scale=0; $layer_remaining / $lrate" | bc 2>/dev/null || echo "0")
                            if [ "$leta" -gt 0 ] 2>/dev/null; then
                                local lh=$((leta / 3600))
                                local lm=$(( (leta % 3600) / 60 ))
                                local ls=$((leta % 60))
                                layer_eta=$(printf "~%dh%02dm%02ds" "$lh" "$lm" "$ls")
                            fi
                        fi
                        echo "$layer_solved $now $layer_eta" > "$layer_snap"
                    else
                        layer_eta="$lp_eta"
                    fi
                else
                    echo "$layer_solved $now -" > "$layer_snap"
                fi
                if [ -n "$layer_eta" ] && [ "$layer_eta" != "-" ]; then
                    status="▶ solving  $layer_eta"
                else
                    status="▶ solving"
                fi
            else
                status="paused"
            fi
        fi

        grand_total=$((grand_total + layer_total))
        grand_solved=$((grand_solved + layer_solved))

        local pct=0
        if [ "$layer_total" -gt 0 ]; then
            pct=$((layer_solved * 100 / layer_total))
        fi

        # Progress bar (15 chars)
        local filled=$((pct * 15 / 100))
        local empty=$((15 - filled))
        local bar=""
        [ "$filled" -gt 0 ] && bar=$(printf '%0.s█' $(seq 1 $filled))
        [ "$empty" -gt 0 ] && bar="${bar}$(printf '%0.s░' $(seq 1 $empty))"

        local depth_label
        if [ "$depth" -eq 0 ]; then
            depth_label="0-1  "
        else
            depth_label="$((depth-1))-${depth}"
            [ ${#depth_label} -lt 5 ] && depth_label="$depth_label "
        fi

        printf "  d%-5s  %9d    %9d    %s %3d%%  %s\n" "$depth_label" "$layer_total" "$layer_solved" "$bar" "$pct" "$status"
    done

    echo "  ─────   ─────────    ─────────    ───────────────────────"

    local grand_pct=0
    if [ "$grand_total" -gt 0 ]; then
        grand_pct=$((grand_solved * 100 / grand_total))
    fi
    local gfilled=$((grand_pct * 15 / 100))
    local gempty=$((15 - gfilled))
    local gbar=""
    [ "$gfilled" -gt 0 ] && gbar=$(printf '%0.s█' $(seq 1 $gfilled))
    [ "$gempty" -gt 0 ] && gbar="${gbar}$(printf '%0.s░' $(seq 1 $gempty))"

    printf "  TOTAL   %9d    %9d    %s %3d%%\n" "$grand_total" "$grand_solved" "$gbar" "$grand_pct"
    echo ""

    # Current layer detail (per-worker + stealer activity)
    local chunks_path="$WORK_DIR/layer_$cur_layer/chunks"
    local chunk_pattern="$chunks_path/input_*"
    if [ "$cur_layer" != "done" ] && ls $chunk_pattern > /dev/null 2>&1; then
        # Count total chunks and completed chunks
        local total_chunks=0
        local done_chunks=0
        local active_chunks=""
        for input in $chunk_pattern; do
            [ -f "$input" ] || continue
            total_chunks=$((total_chunks + 1))
            local cid=$(basename "$input" | sed 's/input_//')
            local ci=$(wc -l < "$input" | tr -d ' ')
            local co=0
            [ -f "$chunks_path/output_$cid" ] && co=$(wc -l < "$chunks_path/output_$cid" | tr -d ' ')
            if [ "$co" -ge "$ci" ]; then
                done_chunks=$((done_chunks + 1))
            elif [ "$co" -gt 0 ]; then
                # Track in-progress chunks for display (skip unstarted)
                local cpct=0
                [ "$ci" -gt 0 ] && cpct=$((co * 100 / ci))
                local cfilled=$((cpct * 10 / 100))
                local cempty=$((10 - cfilled))
                local cbar=""
                [ "$cfilled" -gt 0 ] && cbar=$(printf '%0.s█' $(seq 1 $cfilled))
                [ "$cempty" -gt 0 ] && cbar="${cbar}$(printf '%0.s░' $(seq 1 $cempty))"

                # Per-chunk ETA
                local eta_str=""
                local chunk_snap="$chunks_path/.snap_$cid"
                local chunk_remaining=$((ci - co))
                local now=$(date +%s)
                if [ -f "$chunk_snap" ]; then
                    local prev_eff prev_time prev_eta
                    prev_eff=$(awk '{print $1}' "$chunk_snap")
                    prev_time=$(awk '{print $2}' "$chunk_snap")
                    prev_eta=$(awk '{print $3}' "$chunk_snap")
                    local cdt=$((now - prev_time))
                    local cdc=$((co - prev_eff))
                    if [ "$cdt" -ge 3 ]; then
                        if [ "$cdc" -gt 0 ]; then
                            local crate=$(echo "scale=2; $cdc / $cdt" | bc 2>/dev/null || echo "0")
                            local ceta=$(echo "scale=0; $chunk_remaining / $crate" | bc 2>/dev/null || echo "0")
                            if [ "$ceta" -gt 0 ] 2>/dev/null; then
                                local cm=$((ceta / 60))
                                local cs=$((ceta % 60))
                                eta_str=$(printf "~%dm%02ds" "$cm" "$cs")
                            fi
                        fi
                        echo "$co $now $eta_str" > "$chunk_snap"
                    else
                        eta_str="$prev_eta"
                    fi
                else
                    echo "$co $now -" > "$chunk_snap"
                fi

                local line
                line=$(printf "    %s  %s %3d%%  %7d / %-7d  %s" "$cid" "$cbar" "$cpct" "$co" "$ci" "$eta_str")
                active_chunks="${active_chunks}$(printf '%03d' $((1000 - cpct)))|${line}\n"
            fi
        done

        local remaining_chunks=$((total_chunks - done_chunks))
        printf "  Chunks: %d/%d done  (%d remaining)\n" "$done_chunks" "$total_chunks" "$remaining_chunks"
        echo "  ──────────────────────────────────────────────────"
        if [ -n "$active_chunks" ]; then
            local total_active=$(printf "%b" "$active_chunks" | wc -l | tr -d ' ')
            if [ "${SHOW_ALL_CHUNKS:-0}" = "1" ]; then
                printf "%b" "$active_chunks" | sort -t'|' -k1,1n | sed 's/^[^|]*|//'
            else
                printf "%b" "$active_chunks" | sort -t'|' -k1,1n | sed 's/^[^|]*|//' | head -10
                if [ "$total_active" -gt 10 ]; then
                    printf "    ... and %d more (use --all to show all)\n" "$((total_active - 10))"
                fi
            fi
        else
            echo "    All chunks complete!"
        fi
        echo ""
    fi

    # Elapsed time and ETA
    if [ -f "$WORK_DIR/.start_time" ]; then
        local start=$(cat "$WORK_DIR/.start_time")
        local now=$(date +%s)
        local elapsed=$((now - start))
        local hours=$((elapsed / 3600))
        local mins=$(( (elapsed % 3600) / 60 ))
        local secs=$((elapsed % 60))

        printf "  Elapsed:  %02d:%02d:%02d\n" "$hours" "$mins" "$secs"

        if [ "$grand_solved" -gt 0 ] && [ "$grand_solved" -lt "$grand_total" ]; then
            local remaining=$((grand_total - grand_solved))
            local overall_rate=$(echo "scale=2; $grand_solved / $elapsed" | bc 2>/dev/null || echo "0")

            # Moving rate: compare to last snapshot
            local snapshot="$WORK_DIR/.rate_snapshot"
            local moving_rate=""
            if [ -f "$snapshot" ]; then
                local prev_count prev_time prev_rate
                prev_count=$(awk '{print $1}' "$snapshot")
                prev_time=$(awk '{print $2}' "$snapshot")
                prev_rate=$(awk '{print $3}' "$snapshot")
                local dt=$((now - prev_time))
                local dc=$((grand_solved - prev_count))
                if [ "$dt" -ge 5 ]; then
                    if [ "$dc" -gt 0 ]; then
                        moving_rate=$(echo "scale=2; $dc / $dt" | bc 2>/dev/null || echo "0")
                    else
                        moving_rate="0"
                    fi
                    echo "$grand_solved $now $moving_rate" > "$snapshot"
                else
                    # Reuse last computed rate
                    moving_rate="$prev_rate"
                fi
            else
                echo "$grand_solved $now 0" > "$snapshot"
            fi

            # Append to rate history (for graph)
            local history="$WORK_DIR/.rate_history"
            if [ -n "$moving_rate" ] && [ "$moving_rate" != "" ] && [ "$moving_rate" != "0" ]; then
                echo "$now $moving_rate" >> "$history"
            fi

            # Use moving rate for ETA if available, otherwise overall
            local eta_rate="${moving_rate:-$overall_rate}"
            if [ -n "$eta_rate" ] && [ "$eta_rate" != "0" ] && [ "$eta_rate" != "" ]; then
                local eta_sec=$(echo "scale=0; $remaining / $eta_rate" | bc 2>/dev/null || echo "?")
                if [ "$eta_sec" != "?" ]; then
                    local eh=$((eta_sec / 3600))
                    local em=$(( (eta_sec % 3600) / 60 ))
                    local es=$((eta_sec % 60))
                    printf "  ETA:      %02d:%02d:%02d remaining (based on recent rate)\n" "$eh" "$em" "$es"
                fi
            fi
            printf "  Rate:     ~%s positions/sec (overall)" "$overall_rate"
            if [ -n "$moving_rate" ] && [ "$moving_rate" != "" ]; then
                printf ",  ~%s/sec (recent)" "$moving_rate"
            fi
            printf "\n"

            # Render rate graph (multi-line, 5 rows tall)
            if [ -f "$history" ]; then
                local graph_width=60
                local graph_height=5
                local samples
                samples=$(tail -n "$graph_width" "$history" | awk '{print $2}')
                local count=$(echo "$samples" | wc -l | tr -d ' ')

                if [ "$count" -ge 2 ]; then
                    local min_val max_val
                    min_val=$(echo "$samples" | sort -n | head -1)
                    max_val=$(echo "$samples" | sort -n | tail -1)

                    local range=$(echo "$max_val - $min_val" | bc 2>/dev/null)
                    if [ "$range" = "0" ] || [ -z "$range" ]; then
                        range="1"
                    fi

                    # Build array of normalized values (0 to graph_height*8)
                    local vals=()
                    while IFS= read -r val; do
                        local scaled=$(echo "scale=0; ($val - $min_val) * $graph_height * 8 / $range" | bc 2>/dev/null || echo "0")
                        vals+=("$scaled")
                    done <<< "$samples"

                    local blocks=(" " "▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
                    echo ""
                    printf "  %s/s ┐\n" "$max_val"

                    # Render top to bottom
                    for row in $(seq "$graph_height" -1 1); do
                        local threshold=$(( (row - 1) * 8 ))
                        local line="  "
                        for v in "${vals[@]}"; do
                            local above=$((v - threshold))
                            if [ "$above" -ge 8 ]; then
                                line="${line}${blocks[8]}"
                            elif [ "$above" -gt 0 ]; then
                                line="${line}${blocks[$above]}"
                            else
                                line="${line} "
                            fi
                        done
                        printf "%s│\n" "$line"
                    done

                    printf "  %s/s ┘\n" "$min_val"
                fi
            fi
        fi
        echo ""
    fi

    if [ "$cur_layer" = "done" ]; then
        echo "  All layers complete! Book: $SCRIPT_DIR/7x6.book"
        echo ""
        return 0
    fi

    # Return whether all done (0 = done, 2 = in progress)
    if [ "$grand_total" -gt 0 ] && [ "$grand_solved" -ge "$grand_total" ]; then
        return 0
    fi
    return 2
}

live_watch() {
    local interval="${1:-5}"
    local rc=0

    trap "exit 0" INT TERM

    while true; do
        rc=0
        local buf
        buf=$(show_status 2>&1) || rc=$?
        clear
        printf "%s\n" "$buf"
        if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
            break
        fi
        printf "  Refreshing every %ss — Ctrl+C to stop\n" "$interval"
        sleep "$interval"
    done
}

# ─── Handle subcommands ──────────────────────────────────────────────────────

if [ "${1:-}" = "status" ]; then
    [[ " $* " == *" --all "* ]] && export SHOW_ALL_CHUNKS=1
    show_status || true
    exit 0
fi

if [ "${1:-}" = "watch" ]; then
    [[ " $* " == *" --all "* ]] && export SHOW_ALL_CHUNKS=1
    # Get interval: use first numeric arg after "watch", default 5
    local_interval=5
    for arg in "${@:2}"; do
        [[ "$arg" =~ ^[0-9]+$ ]] && local_interval="$arg"
    done
    live_watch "$local_interval"
    exit 0
fi

# ─── Main: layered generation ────────────────────────────────────────────────

# Re-parse NUM_WORKERS (might have been overwritten by subcommand check)
case "${1:-}" in
    status|watch|combine) ;; # handled above
    *) NUM_WORKERS="${1:-16}" ;;
esac

echo "=== Opening Book Generator (Layered) ==="
echo "Workers: $NUM_WORKERS | Max depth: $MAX_DEPTH"
echo "Strategy: Solve depth 14→12→10→8→6→4→2→0, rebuilding book between layers"
echo ""

mkdir -p "$WORK_DIR"

# Step 1: Generate all positions (once)
POSITIONS_FILE="$WORK_DIR/positions.txt"
if [ ! -f "$POSITIONS_FILE" ]; then
    echo "[$(date '+%H:%M:%S')] Generating all positions up to depth $MAX_DEPTH..."
    "$GENERATOR" "$MAX_DEPTH" > "$POSITIONS_FILE"
    echo "[$(date '+%H:%M:%S')] Generated $(wc -l < "$POSITIONS_FILE" | tr -d ' ') positions"
else
    echo "[$(date '+%H:%M:%S')] Positions file exists ($(wc -l < "$POSITIONS_FILE" | tr -d ' ') positions)"
fi

# Cache per-layer position counts (so status/watch don't scan the full file)
if [ ! -f "$WORK_DIR/layer_counts.txt" ]; then
    echo "[$(date '+%H:%M:%S')] Computing per-layer position counts..."
    awk '{
        l = length
        counts[l]++
    }
    END {
        for (l in counts) print l, counts[l]
    }' "$POSITIONS_FILE" | sort -n > "$WORK_DIR/length_counts.txt"

    # Map lengths to layers: layer N includes lengths N and N-1
    for depth in "${LAYERS[@]}"; do
        total=0
        if [ "$depth" -eq 0 ]; then
            for len in 0 1; do
                c=$(grep "^$len " "$WORK_DIR/length_counts.txt" | awk '{print $2}')
                total=$((total + ${c:-0}))
            done
        else
            for len in $((depth - 1)) $depth; do
                c=$(grep "^$len " "$WORK_DIR/length_counts.txt" | awk '{print $2}')
                total=$((total + ${c:-0}))
            done
        fi
        echo "$depth $total"
    done > "$WORK_DIR/layer_counts.txt"
    echo "[$(date '+%H:%M:%S')] Layer counts cached"
fi

if [ ! -f "$WORK_DIR/.start_time" ]; then
    date +%s > "$WORK_DIR/.start_time"
fi

# Trap Ctrl+C
cleanup() {
    echo ""
    echo "[$(date '+%H:%M:%S')] Interrupted! All progress is saved. Re-run to resume."
    kill 0 2>/dev/null
    exit 1
}
trap cleanup INT TERM

# Step 2: Process each layer
for depth in "${LAYERS[@]}"; do
    layer_dir="$WORK_DIR/layer_$depth"
    mkdir -p "$layer_dir"

    # Skip completed layers
    if [ -f "$layer_dir/.done" ]; then
        echo "[$(date '+%H:%M:%S')] Layer d${depth}: already complete"
        continue
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$(date '+%H:%M:%S')] Layer d${depth}: starting"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Extract positions for this layer
    if [ ! -f "$layer_dir/positions.txt" ]; then
        positions_for_layer "$depth" "$layer_dir/positions.txt"
        echo "[$(date '+%H:%M:%S')] Layer d${depth}: $(wc -l < "$layer_dir/positions.txt" | tr -d ' ') positions"
    fi

    layer_total=$(wc -l < "$layer_dir/positions.txt" | tr -d ' ')

    if [ "$layer_total" -eq 0 ]; then
        touch "$layer_dir/.done"
        echo "[$(date '+%H:%M:%S')] Layer d${depth}: no positions, skipping"
        continue
    fi

    # Split into many small chunks for work-queue load balancing
    # More chunks than workers = natural load balancing without stealing
    chunks_dir="$layer_dir/chunks"
    num_chunks=$((NUM_WORKERS * 4))
    [ "$num_chunks" -gt "$layer_total" ] && num_chunks="$layer_total"
    # Use 3-digit IDs to support up to 999 chunks
    chunk_digits=3

    if [ ! -f "$chunks_dir/.split_done" ]; then
        rm -rf "$chunks_dir"
        mkdir -p "$chunks_dir"

        if command -v gsplit > /dev/null 2>&1; then
            gsplit -n "l/$num_chunks" -a "$chunk_digits" -d "$layer_dir/positions.txt" "$chunks_dir/input_"
        else
            awk -v n="$num_chunks" -v dir="$chunks_dir" '{
                worker = (NR - 1) % n
                printf "%s\n", $0 >> (dir "/input_" sprintf("%03d", worker))
            }' "$layer_dir/positions.txt"
        fi

        touch "$chunks_dir/.split_done"
        echo "[$(date '+%H:%M:%S')] Split into $num_chunks chunks"
    fi

    # Determine book flag for solver
    book_flag=""
    if [ -f "$SCRIPT_DIR/7x6.book" ]; then
        book_flag="-b $SCRIPT_DIR/7x6.book"
        echo "[$(date '+%H:%M:%S')] Using book from previous layers"
    fi

    # Fix truncated output line in a file
    fix_truncated() {
        local f="$1"
        if [ -s "$f" ]; then
            local last_byte=$(tail -c 1 "$f" | xxd -p)
            if [ "$last_byte" != "0a" ] && [ "$last_byte" != "" ]; then
                local tmp=$(mktemp)
                head -n -1 "$f" > "$tmp"
                mv "$tmp" "$f"
            fi
        fi
    }

    # Solve a single chunk with resume support
    solve_chunk() {
        local cid="$1"
        local input="$chunks_dir/input_$cid"
        local output="$chunks_dir/output_$cid"
        local log="$chunks_dir/log_$cid"

        [ ! -f "$input" ] && return

        local total=$(wc -l < "$input" | tr -d ' ')
        local done_count=0

        if [ -f "$output" ]; then
            fix_truncated "$output"
            done_count=$(wc -l < "$output" | tr -d ' ')
        fi

        if [ "$done_count" -ge "$total" ]; then
            return
        fi

        tail -n +"$((done_count + 1))" "$input" | "$SOLVER" $book_flag >> "$output" 2>> "$log"
    }

    echo "[$(date '+%H:%M:%S')] Launching $num_chunks chunk processes..."

    # One process per chunk — OS handles scheduling across cores
    for input in "$chunks_dir"/input_*; do
        [ -f "$input" ] || continue
        cid=$(basename "$input" | sed 's/input_//')
        solve_chunk "$cid" &
    done
    wait

    # Combine — no dedup needed, each position solved exactly once
    cat "$chunks_dir"/output_* > "$layer_dir/scored.txt" 2>/dev/null || true
    local_solved=$(wc -l < "$layer_dir/scored.txt" | tr -d ' ')

    if [ "$local_solved" -ge "$layer_total" ]; then
        touch "$layer_dir/.done"
        echo "[$(date '+%H:%M:%S')] Layer d${depth}: complete ($local_solved positions)"

        # Rebuild book with all completed layers
        build_book_from_scored || true
    else
        echo "[$(date '+%H:%M:%S')] Layer d${depth}: incomplete ($local_solved/$layer_total). Re-run to resume."
        exit 1
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "=== All layers complete! ==="
echo "Book file: $SCRIPT_DIR/7x6.book ($(ls -lh "$SCRIPT_DIR/7x6.book" | awk '{print $5}'))"
echo "Use with solver: echo '4453' | ./c4solver -b 7x6.book"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
