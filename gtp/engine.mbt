///|
/// A text-based Go Text Protocol (GTP) engine over the rules engine.
///
/// The engine is a reusable *library component*: callers feed it command
/// lines (from a socket, a REPL, a test harness, a subprocess pipe...) and
/// receive ready-made GTP responses. It performs no I/O itself, so it can
/// be embedded in GUI clients, analysis services or test suites alike.
///
/// Supported commands: `protocol_version`, `name`, `version`,
/// `known_command`, `list_commands`, `boardsize`, `clear_board`, `komi`,
/// `play`, `genmove`, `undo`, `showboard`, `final_score`, `quit`.
pub struct GtpEngine {
  priv mut game : @moonbaduk.Game
  priv mut quit_requested : Bool
  priv engine_name : String
  priv engine_version : String
}

///|
/// Response of one GTP command: the raw response text (already including
/// the `=`/`?` marker and the trailing blank line) plus whether the
/// command asked the controlling program to shut down.
pub struct GtpResponse {
  /// Full response text, e.g. `"= 2\n\n"` or `"? illegal move\n\n"`.
  text : String
  /// True when the last command was `quit`.
  quit : Bool
}

///|
/// Creates a GTP engine with the given identity strings (reported by the
/// `name` and `version` commands).
pub fn GtpEngine::new(engine_name : String, engine_version : String) -> GtpEngine {
  { game: @moonbaduk.Game::new(19, 7.5), quit_requested: false, engine_name, engine_version }
}

///|
/// The current game state (a defensive copy of the board).
pub fn GtpEngine::board(self : GtpEngine) -> @moonbaduk.Board {
  self.game.board()
}

///|
/// True after a `quit` command has been processed.
pub fn GtpEngine::quit_requested(self : GtpEngine) -> Bool {
  self.quit_requested
}

///|
/// The command table reported by `list_commands`.
pub fn GtpEngine::command_list() -> Array[String] {
  [
    "protocol_version", "name", "version", "known_command", "list_commands",
    "boardsize", "clear_board", "komi", "play", "genmove", "undo",
    "showboard", "final_score", "quit",
  ]
}

///|
/// Processes one command line (with or without an id) and returns the
/// GTP-formatted response. Invalid input yields a `?` error response —
/// the engine never panics on malformed input.
pub fn GtpEngine::handle(self : GtpEngine, line : String) -> GtpResponse {
  let tokens = tokenize(line)
  if tokens.length() == 0 {
    return { text: "", quit: false }
  }
  // an optional numeric id prefixes the command
  let mut idx = 0
  let mut id = ""
  if is_all_digits(tokens[0]) {
    id = tokens[0]
    idx = 1
  }
  if idx >= tokens.length() {
    return { text: "", quit: false }
  }
  let cmd = tokens[idx]
  let args : Array[String] = []
  for j in (idx + 1)..<tokens.length() {
    args.push(tokens[j])
  }
  let body : String = match cmd {
    "protocol_version" => "2"
    "name" => self.engine_name
    "version" => self.engine_version
    "known_command" =>
      if args.length() == 1 {
        let c = args[0]
        let mut found = false
        for k in GtpEngine::command_list() {
          if k == c {
            found = true
          }
        }
        if found {
          "true"
        } else {
          "false"
        }
      } else {
        return err(id, "known_command needs exactly one argument")
      }
    "list_commands" => {
      let buf = StringBuilder()
      for i, c in GtpEngine::command_list() {
        if i > 0 {
          buf.write_string("\n")
        }
        buf.write_string(c)
      }
      buf.to_string()
    }
    "boardsize" =>
      if args.length() != 1 {
        return err(id, "boardsize needs one argument")
      } else {
        match parse_int(args[0]) {
          Some(n) => {
            if n < 2 || n > 26 {
              return err(id, "unacceptable size")
            }
            let komi = self.game.komi()
            self.game = @moonbaduk.Game::new(n, komi)
            ""
          }
          None => return err(id, "boardsize not an integer")
        }
      }
    "clear_board" => {
      let size = self.game.size()
      let komi = self.game.komi()
      self.game = @moonbaduk.Game::new(size, komi)
      ""
    }
    "komi" =>
      if args.length() != 1 {
        return err(id, "komi needs one argument")
      } else {
        match parse_float(args[0]) {
          Some(k) => {
            self.game.set_komi(k)
            ""
          }
          None => return err(id, "komi not a float")
        }
      }
    "play" =>
      if args.length() != 2 {
        return err(id, "play needs two arguments: color and vertex")
      } else {
        match parse_color(args[0]) {
          None => return err(id, "invalid color")
          Some(color) =>
            match parse_vertex(args[1], self.game.size()) {
              Pass => {
                self.game.play_pass(color)
                ""
              }
              At(r, c) =>
                match self.game.play_stone(color, r, c) {
                  Ok(_) => ""
                  Err(e) => return err(id, e.message())
                }
              IllegalVertex => return err(id, "invalid vertex")
            }
        }
      }
    "genmove" =>
      if args.length() != 1 {
        return err(id, "genmove needs one argument: color")
      } else {
        match parse_color(args[0]) {
          None => return err(id, "invalid color")
          Some(color) => {
            let pts = self.game.legal_points(color)
            if pts.length() == 0 {
              self.game.play_pass(color)
              "pass"
            } else {
              // deterministic reference mover: the first legal point in
              // scan order. Real engines replace the whole component.
              let (r, c) = pts[0]
              let _ = self.game.play_stone(color, r, c)
              vertex_name(r, c, self.game.size())
            }
          }
        }
      }
    "undo" =>
      if self.game.undo() {
        ""
      } else {
        return err(id, "cannot undo")
      }
    "showboard" => self.game.board().render()
    "final_score" => self.game.final_score()
    "quit" => {
      self.quit_requested = true
      ""
    }
    _ => return err(id, "unknown command")
  }
  let prefix = if id == "" {
    "="
  } else {
    "=\{id}"
  }
  if body == "" {
    { text: "\{prefix}\n\n", quit: self.quit_requested }
  } else {
    { text: "\{prefix} \{body}\n\n", quit: self.quit_requested }
  }
}

///|
fn err(id : String, msg : String) -> GtpResponse {
  let prefix = if id == "" {
    "?"
  } else {
    "?\{id}"
  }
  { text: "\{prefix} \{msg}\n\n", quit: false }
}

///|
priv enum Vertex {
  At(Int, Int)
  Pass
  IllegalVertex
}

///|
fn tokenize(line : String) -> Array[String] {
  let acc : Array[String] = []
  let buf = StringBuilder()
  let mut in_token = false
  for ch in line {
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      if in_token {
        acc.push(buf.to_string())
        buf.reset()
        in_token = false
      }
    } else {
      buf.write_char(ch)
      in_token = true
    }
  }
  if in_token {
    acc.push(buf.to_string())
  }
  acc
}

///|
fn is_all_digits(s : String) -> Bool {
  let mut n = 0
  let mut digits = true
  for ch in s {
    n += 1
    if !(ch >= '0' && ch <= '9') {
      digits = false
    }
  }
  n > 0 && digits
}

///|
fn parse_int(s : String) -> Int? {
  if !is_all_digits(s) {
    return None
  }
  let mut n = 0
  for ch in s {
    n = n * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
fn parse_float(s : String) -> Double? {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  if chars.length() == 0 {
    return None
  }
  let mut i = 0
  let mut sign = 1.0
  if chars[0] == '-' {
    sign = -1.0
    i = 1
  } else if chars[0] == '+' {
    i = 1
  }
  let mut int_part = 0
  let mut seen_digit = false
  while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
    int_part = int_part * 10 + (chars[i].to_int() - '0'.to_int())
    seen_digit = true
    i += 1
  }
  let mut frac = 0.0
  let mut scale = 0.1
  if i < chars.length() && chars[i] == '.' {
    i += 1
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      frac += (chars[i].to_int() - '0'.to_int()).to_double() * scale
      scale *= 0.1
      seen_digit = true
      i += 1
    }
  }
  if !seen_digit || i != chars.length() {
    return None
  }
  Some(sign * (int_part.to_double() + frac))
}

///|
fn parse_color(s : String) -> @moonbaduk.Stone? {
  let lowered = s.to_lower()
  if lowered == "b" || lowered == "black" {
    Some(@moonbaduk.Black)
  } else if lowered == "w" || lowered == "white" {
    Some(@moonbaduk.White)
  } else {
    None
  }
}

///|
fn parse_vertex(s : String, size : Int) -> Vertex {
  let lowered = s.to_lower()
  if lowered == "pass" {
    return Pass
  }
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  if chars.length() < 2 {
    return IllegalVertex
  }
  let col_ch = chars[0].to_ascii_lowercase()
  if !(col_ch >= 'a' && col_ch <= 'z') {
    return IllegalVertex
  }
  // digits: 1-based row, GTP skips the letter 'i'
  let mut row = 0
  for j in 1..<chars.length() {
    let ch = chars[j]
    if !(ch >= '0' && ch <= '9') {
      return IllegalVertex
    }
    row = row * 10 + (ch.to_int() - '0'.to_int())
  }
  if row < 1 {
    return IllegalVertex
  }
  let col = if col_ch > 'i' {
    col_ch.to_int() - 'a'.to_int() - 1
  } else {
    col_ch.to_int() - 'a'.to_int()
  }
  let r = size - row
  if r < 0 || r >= size || col < 0 || col >= size {
    return IllegalVertex
  }
  At(r, col)
}

///|
fn vertex_name(row : Int, col : Int, size : Int) -> String {
  let letters : Array[Char] = []
  for ch in "ABCDEFGHJKLMNOPQRSTUVWXYZ" {
    letters.push(ch)
  }
  let buf = StringBuilder()
  buf.write_char(letters[col])
  // GTP rows are 1-based from the bottom and skip the letter 'i'
  buf.write_string("\{size - row}")
  buf.to_string()
}
