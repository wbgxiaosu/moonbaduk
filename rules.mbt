///|
/// Why a move was rejected.
pub(all) enum PlayError {
  OutOfBounds
  Occupied
  /// The move fills the player's last own liberty without capturing.
  Suicide
  /// Immediate recapture of a single ko stone.
  KoViolation
  /// The move would recreate an earlier whole-board position
  /// (positional superko, Chinese rules).
  SuperkoViolation
  GameOver
} derive(Eq, Debug)

///|
pub extend PlayError with Eq::{equal, not_equal}

///|
pub extend PlayError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn PlayError::message(self : PlayError) -> String {
  match self {
    OutOfBounds => "move is out of bounds"
    Occupied => "point is occupied"
    Suicide => "move is suicide"
    KoViolation => "immediate ko recapture is forbidden"
    SuperkoViolation => "move would repeat a previous board position (superko)"
    GameOver => "the game is already over"
  }
}

///|
struct Snapshot {
  board : Board
  turn : Stone
  caps_black : Int
  caps_white : Int
  ko_point : Option[Int]
  passes : Int
  over : Bool
  /// The position key inserted into the history by this move ("" for a
  /// pass, which inserts nothing). [undo] removes exactly this key.
  history_key : String
}

///|
/// A Go game under Chinese rules (area scoring, positional superko).
/// Black moves first on an empty board; handicap games place stones with
/// [Game::setup_stone] and start with White to play.
pub struct Game {
  priv mut board : Board
  priv mut turn : Stone
  priv mut caps_black : Int
  priv mut caps_white : Int
  priv mut ko_point : Option[Int]
  /// Sorted position keys of every position reached so far (including the
  /// initial one), used for positional-superko detection.
  priv history : Array[String]
  priv mut passes : Int
  priv mut over : Bool
  priv mut komi : Double
  priv undo_stack : Array[Snapshot]
}

///|
/// Creates a new empty game. `komi` is added to White's score (7.5 is the
/// usual Chinese-rules value).
pub fn Game::new(size : Int, komi : Double) -> Game {
  let board = Board::new(size)
  let g : Game = {
    board,
    turn: Black,
    caps_black: 0,
    caps_white: 0,
    ko_point: None,
    history: [],
    passes: 0,
    over: false,
    komi,
    undo_stack: [],
  }
  g.push_history()
  g
}

///|
fn Game::push_history(self : Game) -> Unit {
  let key = self.board.position_key()
  let pos = binary_search(self.history, key)
  self.history.insert(pos, key)
}

///|
/// Sorted-array binary search: returns the insertion index of `key`.
fn binary_search(arr : Array[String], key : String) -> Int {
  let mut lo = 0
  let mut hi = arr.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if arr[mid] < key {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
fn Game::snapshot(self : Game, history_key : String) -> Snapshot {
  let s : Snapshot = {
    board: self.board.copy(),
    turn: self.turn,
    caps_black: self.caps_black,
    caps_white: self.caps_white,
    ko_point: self.ko_point,
    passes: self.passes,
    over: self.over,
    history_key,
  }
  s
}

///|
pub fn Game::size(self : Game) -> Int {
  self.board.size
}

///|
pub fn Game::komi(self : Game) -> Double {
  self.komi
}

///|
pub fn Game::set_komi(self : Game, komi : Double) -> Unit {
  self.komi = komi
}

///|
/// The color to move next.
pub fn Game::turn(self : Game) -> Stone {
  self.turn
}

///|
/// A defensive copy of the current board.
pub fn Game::board(self : Game) -> Board {
  self.board.copy()
}

///|
/// Stones captured by (black, white).
pub fn Game::captures(self : Game) -> (Int, Int) {
  (self.caps_black, self.caps_white)
}

///|
pub fn Game::consecutive_passes(self : Game) -> Int {
  self.passes
}

///|
pub fn Game::is_over(self : Game) -> Bool {
  self.over
}

///|
/// The forbidden recapture point after a ko-shaped capture, if any.
pub fn Game::ko_point(self : Game) -> Option[(Int, Int)] {
  match self.ko_point {
    Some(i) => Some((self.board.row_of(i), self.board.col_of(i)))
    None => None
  }
}

///|
/// Places (or clears) a stone without turn handling — used for handicap
/// stones and SGF setup properties. Resets the superko history to the
/// resulting position. Illegal points are silently ignored.
pub fn Game::setup_stone(
  self : Game,
  row : Int,
  col : Int,
  stone : Stone,
) -> Unit {
  if self.board.in_bounds(row, col) {
    self.board.set(row, col, stone)
    self.history.clear()
    self.push_history()
  }
}

///|
/// Replaces the superko history with the given position keys (sorted
/// automatically). Used when loading a position from SGF/GTP where the
/// earlier positions of the game are unknown.
pub fn Game::set_history(self : Game, keys : Array[String]) -> Unit {
  self.history.clear()
  for k in keys {
    let pos = binary_search(self.history, k)
    self.history.insert(pos, k)
  }
}

///|
/// Declares (or revokes) the game-over state. Two consecutive passes end a
/// game automatically; this is provided for adjudication tools.
pub fn Game::set_over(self : Game, over : Bool) -> Unit {
  self.over = over
}

///|
/// Plays a stone of color `player` at (row, col). Out-of-turn coordinates
/// are accepted (the mover defines the color), matching GTP semantics.
/// Returns the number of captured stones.
pub fn Game::play_stone(
  self : Game,
  player : Stone,
  row : Int,
  col : Int,
) -> Result[Int, PlayError] {
  if player is Empty {
    return Err(Occupied)
  }
  if self.over {
    return Err(GameOver)
  }
  if !(self.board.in_bounds(row, col)) {
    return Err(OutOfBounds)
  }
  let i = self.board.idx(row, col)
  if !(self.cells_get(i) is Empty) {
    return Err(Occupied)
  }
  if self.ko_point == Some(i) {
    return Err(KoViolation)
  }
  let nb = self.board.copy()
  nb.set_at(i, player)
  let opp = player.opponent()
  let mut captured = 0
  let mut captured_one : Option[Int] = None
  let removed : Array[Bool] = Array::make(nb.size * nb.size, false)
  for n in nb.neighbors(i) {
    if nb.get_at(n) == opp && !removed[n] {
      let grp = nb.group_at(n)
      if grp.liberties.length() == 0 {
        for s in grp.stones {
          nb.set_at(s, Empty)
          removed[s] = true
          captured += 1
          captured_one = Some(s)
        }
      }
    }
  }
  let own = nb.group_at(i)
  if own.liberties.length() == 0 && captured == 0 {
    return Err(Suicide)
  }
  // positional superko: reject recreation of any earlier position
  let key = nb.position_key()
  let pos = binary_search(self.history, key)
  if pos < self.history.length() && self.history[pos] == key {
    return Err(SuperkoViolation)
  }
  // simple ko: single stone captured, single-stone group with one liberty
  let new_ko : Option[Int] = if captured == 1 &&
    own.stones.length() == 1 &&
    own.liberties.length() == 1 {
    captured_one
  } else {
    None
  }
  // commit
  self.undo_stack.push(self.snapshot(key))
  self.board = nb
  match player {
    Black => self.caps_black += captured
    White => self.caps_white += captured
    Empty => ()
  }
  self.ko_point = new_ko
  self.history.insert(pos, key)
  self.turn = player.opponent()
  self.passes = 0
  Ok(captured)
}

///|
fn Game::cells_get(self : Game, i : Int) -> Stone {
  self.board.get_at(i)
}

///|
/// Plays a stone for the side to move.
pub fn Game::play(self : Game, row : Int, col : Int) -> Result[Int, PlayError] {
  self.play_stone(self.turn, row, col)
}

///|
/// The given color passes. Two consecutive passes end the game.
pub fn Game::play_pass(self : Game, player : Stone) -> Unit {
  if self.over {
    return
  }
  self.undo_stack.push(self.snapshot(""))
  self.ko_point = None
  self.passes += 1
  if self.passes >= 2 {
    self.over = true
  }
  self.turn = player.opponent()
}

///|
/// Undoes the last move or pass. Returns false when nothing to undo.
pub fn Game::undo(self : Game) -> Bool {
  match self.undo_stack.pop() {
    Some(s) => {
      self.board = s.board
      self.turn = s.turn
      self.caps_black = s.caps_black
      self.caps_white = s.caps_white
      self.ko_point = s.ko_point
      self.passes = s.passes
      self.over = s.over
      if s.history_key.length() > 0 {
        let p = binary_search(self.history, s.history_key)
        if p < self.history.length() && self.history[p] == s.history_key {
          let _ = self.history.remove(p)
        }
      }
      true
    }
    None => false
  }
}

///|
/// Area score (Chinese rules): stones on the board plus empty regions
/// enclosed by a single color. Neutral points (dame) count for nobody.
/// Returns (black, white) where white already includes komi.
pub fn Game::score_area(self : Game) -> (Double, Double) {
  let size = self.board.size
  let mut black_stones = 0
  let mut white_stones = 0
  let visited : Array[Bool] = Array::make(size * size, false)
  let mut terr_black = 0
  let mut terr_white = 0
  for i in 0..<(size * size) {
    match self.board.get_at(i) {
      Black => black_stones += 1
      White => white_stones += 1
      Empty =>
        if !visited[i] {
          // flood fill this empty region
          let mut sees_black = false
          let mut sees_white = false
          let mut count = 0
          let stack : Array[Int] = [i]
          visited[i] = true
          while stack.length() > 0 {
            let cur = stack.pop().unwrap()
            count += 1
            for n in self.board.neighbors(cur) {
              match self.board.get_at(n) {
                Black => sees_black = true
                White => sees_white = true
                Empty =>
                  if !visited[n] {
                    visited[n] = true
                    stack.push(n)
                  }
              }
            }
          }
          if sees_black && !sees_white {
            terr_black += count
          } else if sees_white && !sees_black {
            terr_white += count
          }
        }
    }
  }
  ((black_stones + terr_black).to_double(), (white_stones + terr_white).to_double() + self.komi)
}

///|
/// Result string in GTP/SGF style: `B+2.5`, `W+0.5` or `0` (jigo).
/// Returns `void` when the game has not ended with two passes.
pub fn Game::final_score(self : Game) -> String {
  if !(self.over) {
    return "void"
  }
  let (b, w) = self.score_area()
  let diff = b - w
  if diff > 0.0 {
    "B+\{diff}"
  } else if diff < 0.0 {
    let ad = 0.0 - diff
    "W+\{ad}"
  } else {
    "0"
  }
}

///|
/// All points where `player` may legally play right now (ko, superko and
/// suicide excluded). Used by GTP `genmove` and by test tooling.
pub fn Game::legal_points(self : Game, player : Stone) -> Array[(Int, Int)] {
  let acc : Array[(Int, Int)] = []
  if player is Empty || self.over {
    return acc
  }
  let size = self.board.size
  for i in 0..<(size * size) {
    if self.cells_get(i) is Empty && self.ko_point != Some(i) {
      let r = self.board.row_of(i)
      let c = self.board.col_of(i)
      if self.play_stone(player, r, c) is Ok(_) {
        acc.push((r, c))
        let _ = self.undo()
      }
    }
  }
  acc
}
