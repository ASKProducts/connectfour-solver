/*
 * connectfour-solver WASM wrapper
 * Copyright (C) 2024 ASKProducts
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * Based on Connect4 Game Solver by Pascal Pons <http://connect4.gamesolver.org>
 */

#include "Solver.hpp"
#include "Position.hpp"
#include <cstring>

using namespace GameSolver::Connect4;

static Solver solver;

extern "C" {

void solver_init() {
  solver.reset();
}

int solver_load_book(const uint8_t* data, int length) {
  return solver.loadBookFromBuffer(data, (size_t)length) ? 1 : 0;
}

int solver_solve(const char* pos_str, int weak) {
  Position P;
  if (pos_str != nullptr && strlen(pos_str) > 0) {
    if (P.play(std::string(pos_str)) != strlen(pos_str)) {
      return Solver::INVALID_MOVE;
    }
  }
  return solver.solve(P, weak != 0);
}

int solver_analyze(const char* pos_str, int weak, int* scores_out) {
  Position P;
  if (pos_str != nullptr && strlen(pos_str) > 0) {
    if (P.play(std::string(pos_str)) != strlen(pos_str)) {
      return -1;
    }
  }
  std::vector<int> scores = solver.analyze(P, weak != 0);
  for (int i = 0; i < Position::WIDTH; i++) {
    scores_out[i] = scores[i];
  }
  return 0;
}

void solver_reset() {
  solver.reset();
}

unsigned long long solver_get_node_count() {
  return solver.getNodeCount();
}

} // extern "C"
