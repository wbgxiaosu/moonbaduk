///|
/// Parses an integer prefix like `"19"` out of an SGF value such as
/// `"19"` or a rectangular `"19:19"` (returns the first component).
fn parse_int_prefix(v : String) -> Int? {
  let chars : Array[Char] = []
  for c in v {
    if c >= '0' && c <= '9' {
      chars.push(c)
    } else {
      break
    }
  }
  if chars.length() == 0 {
    return None
  }
  let mut n = 0
  for c in chars {
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
/// Lenient komi parser: accepts values like `7.5`, `550` (points*100 as
/// written by some tools) and falls back to 0.0 on garbage.
fn parse_komi(v : String) -> Double {
  let mut sign = 1.0
  let chars : Array[Char] = []
  for c in v {
    if c == '-' && chars.length() == 0 {
      sign = -1.0
    } else if (c >= '0' && c <= '9') || c == '.' {
      chars.push(c)
    } else if !chars.is_empty() {
      break
    }
  }
  let mut int_part = 0
  let mut frac = 0
  let mut frac_scale = 1
  let mut seen_dot = false
  for c in chars {
    if c == '.' {
      seen_dot = true
    } else if seen_dot {
      frac = frac * 10 + (c.to_int() - '0'.to_int())
      frac_scale = frac_scale * 10
    } else {
      int_part = int_part * 10 + (c.to_int() - '0'.to_int())
    }
  }
  sign * (int_part.to_double() + frac.to_double() / frac_scale.to_double())
}

///|
/// Decodes one SGF point value (`"pd"` style) into (row, col).
/// Returns None for passes (`""`, `"tt"`) and malformed values.
pub fn parse_sgf_point(v : String) -> (Int, Int)? {
  let chars : Array[Char] = []
  for c in v {
    chars.push(c)
  }
  if chars.length() != 2 {
    return None
  }
  let c0 = chars[0].to_ascii_lowercase()
  let c1 = chars[1].to_ascii_lowercase()
  if !(c0 >= 'a' && c0 <= 'z') || !(c1 >= 'a' && c1 <= 'z') {
    return None
  }
  // FF[4]: the value "tt" is a pass for boards up to 19x19
  if c0 == 't' && c1 == 't' {
    return None
  }
  Some((c1.to_int() - 'a'.to_int(), c0.to_int() - 'a'.to_int()))
}

///|
/// Result of replaying an SGF game tree against the rules engine.
pub struct ReplayReport {
  /// The game state after the main line has been applied.
  game : @moonbaduk.Game
  /// Number of moves (B/W properties) applied.
  moves : Int
  /// Notes about ignored or rejected data (illegal moves, bad values...).
  warnings : Array[String]
}

///|
/// Replays the main line (first variation at each branch) of the tree on a
/// fresh game. Setup stones (`AB`/`AW`) and board size (`SZ`) are honoured;
/// illegal moves are skipped with a warning instead of aborting.
pub fn SgfTree::replay(self : SgfTree) -> Result[ReplayReport, String] {
  let root = self.root()
  let size = match root.get("SZ") {
    Some(v) =>
      match parse_int_prefix(v) {
        Some(n) => n
        None => return Err("bad SZ value: \{v}")
      }
    None => 19
  }
  let komi = match root.get("KM") {
    Some(v) => parse_komi(v)
    None => 0.0
  }
  let game = @moonbaduk.Game::new(size, komi)
  let warnings : Array[String] = []
  for v in root.get_all("AB") {
    match parse_sgf_point(v) {
      Some((r, c)) =>
        if game.size() <= r || game.size() <= c {
          warnings.push("AB point out of bounds: \{v}")
        } else {
          game.setup_stone(r, c, @moonbaduk.Black)
        }
      None => warnings.push("bad AB value: \{v}")
    }
  }
  for v in root.get_all("AW") {
    match parse_sgf_point(v) {
      Some((r, c)) =>
        if game.size() <= r || game.size() <= c {
          warnings.push("AW point out of bounds: \{v}")
        } else {
          game.setup_stone(r, c, @moonbaduk.White)
        }
      None => warnings.push("bad AW value: \{v}")
    }
  }
  let mut moves = 0
  let line = self.main_line()
  for i, node in line {
    for entry in [
      (@moonbaduk.Black, "B"),
      (@moonbaduk.White, "W"),
    ] {
      let (color, id) = entry
      for mv in node.get_all(id) {
        match parse_sgf_point(mv) {
          Some((r, c)) => {
            moves += 1
            match game.play_stone(color, r, c) {
              Ok(_) => ()
              Err(e) =>
                warnings.push("node \{i}: move \{id}[\{mv}] rejected: \{e.message()}")
            }
          }
          None =>
            // "" or "tt" is a pass; anything else is malformed
            if mv != "" && mv != "tt" {
              warnings.push("node \{i}: bad \{id} value: \{mv}")
            } else {
              game.play_pass(color)
            }
        }
      }
    }
  }
  Ok({ game, moves, warnings, })
}
