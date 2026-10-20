///|
/// A point on the board: empty, black stone or white stone.
pub(all) enum Stone {
  Empty
  Black
  White
} derive(Eq, Debug)

///|
pub extend Stone with Eq::{equal, not_equal}

///|
pub extend Stone with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The opposing color. `Empty` maps to `Empty`.
pub fn Stone::opponent(self : Stone) -> Stone {
  match self {
    Black => White
    White => Black
    Empty => Empty
  }
}

///|
/// Short marker used in board rendering and position keys.
pub fn Stone::marker(self : Stone) -> String {
  match self {
    Empty => "."
    Black => "X"
    White => "O"
  }
}

///|
pub fn Stone::is_stone(self : Stone) -> Bool {
  self is Black || self is White
}

///|
/// Result of a flood-fill over one connected group of same-colored stones.
pub struct GroupInfo {
  /// Indices of the stones in the group.
  stones : Array[Int]
  /// Indices of the empty points adjacent to the group (deduplicated).
  liberties : Array[Int]
}

///|
/// A square Go board. Rows and columns are 0-based with row 0 at the top
/// and column 0 on the left (SGF convention). Board sizes 2..=26 are allowed;
/// out-of-range sizes are clamped so the type is always safe to use.
pub struct Board {
  size : Int
  priv cells : Array[Stone]
}

///|
pub fn Board::new(size : Int) -> Board {
  let s = if size < 2 {
    2
  } else if size > 26 {
    26
  } else {
    size
  }
  { size: s, cells: Array::make(s * s, Empty) }
}

///|
pub fn Board::idx(self : Board, row : Int, col : Int) -> Int {
  row * self.size + col
}

///|
pub fn Board::row_of(self : Board, i : Int) -> Int {
  i / self.size
}

///|
pub fn Board::col_of(self : Board, i : Int) -> Int {
  i % self.size
}

///|
pub fn Board::in_bounds(self : Board, row : Int, col : Int) -> Bool {
  row >= 0 && row < self.size && col >= 0 && col < self.size
}

///|
pub fn Board::get(self : Board, row : Int, col : Int) -> Stone {
  self.cells[self.idx(row, col)]
}

///|
pub fn Board::get_at(self : Board, i : Int) -> Stone {
  self.cells[i]
}

///|
pub fn Board::set(self : Board, row : Int, col : Int, stone : Stone) -> Unit {
  self.cells[self.idx(row, col)] = stone
}

///|
pub fn Board::set_at(self : Board, i : Int, stone : Stone) -> Unit {
  self.cells[i] = stone
}

///|
/// Orthogonal neighbors of a point (2 on a corner, 3 on a side, 4 inside).
pub fn Board::neighbors(self : Board, i : Int) -> Array[Int] {
  let row = self.row_of(i)
  let col = self.col_of(i)
  let acc : Array[Int] = []
  if row > 0 {
    acc.push(self.idx(row - 1, col))
  }
  if row < self.size - 1 {
    acc.push(self.idx(row + 1, col))
  }
  if col > 0 {
    acc.push(self.idx(row, col - 1))
  }
  if col < self.size - 1 {
    acc.push(self.idx(row, col + 1))
  }
  acc
}

///|
/// Flood-fills the group containing point `i`. Returns a group with empty
/// arrays when the point is `Empty`.
pub fn Board::group_at(self : Board, i : Int) -> GroupInfo {
  let stone = self.cells[i]
  if stone is Empty {
    return { stones: [], liberties: [] }
  }
  let seen : Array[Bool] = Array::make(self.size * self.size, false)
  let lib_seen : Array[Bool] = Array::make(self.size * self.size, false)
  let stones : Array[Int] = []
  let liberties : Array[Int] = []
  let stack : Array[Int] = [i]
  seen[i] = true
  while stack.length() > 0 {
    let cur = stack.pop().unwrap()
    stones.push(cur)
    for n in self.neighbors(cur) {
      match self.cells[n] {
        Empty =>
          if !lib_seen[n] {
            lib_seen[n] = true
            liberties.push(n)
          }
        s =>
          if s == stone && !seen[n] {
            seen[n] = true
            stack.push(n)
          }
      }
    }
  }
  { stones, liberties, }
}

///|
/// Deep copy of the board.
pub fn Board::copy(self : Board) -> Board {
  { size: self.size, cells: self.cells.copy() }
}

///|
/// A compact character key describing the full board position, used for
/// positional-superko comparison. Row-major, one char per point.
pub fn Board::position_key(self : Board) -> String {
  let buf = StringBuilder()
  for c in self.cells {
    buf.write_string(match c {
      Empty => "."
      Black => "x"
      White => "o"
    })
  }
  buf.to_string()
}

///|
/// ASCII rendering of the board, row 0 (top) first.
pub fn Board::render(self : Board) -> String {
  let letters : Array[Char] = []
  for ch in "abcdefghijklmnopqrstuvwxyz" {
    letters.push(ch)
  }
  let buf = StringBuilder()
  buf.write_string("   ")
  for c in 0..<self.size {
    buf.write_char(letters[c])
    if c != self.size - 1 {
      buf.write_string(" ")
    }
  }
  buf.write_string("\n")
  for r in 0..<self.size {
    let label = if r + 1 < 10 {
      " \{r + 1}"
    } else {
      "\{r + 1}"
    }
    buf.write_string("\{label} ")
    for c in 0..<self.size {
      buf.write_string(self.get(r, c).marker())
      if c != self.size - 1 {
        buf.write_string(" ")
      }
    }
    buf.write_string("\n")
  }
  buf.to_string()
}
