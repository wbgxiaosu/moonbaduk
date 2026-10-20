// Blackbox tests for the GTP package.

///|
test "gtp: identity and protocol commands" {
  let e = @gtp.GtpEngine::new("moonbaduk", "0.1.0")
  let r1 = e.handle("protocol_version")
  assert_eq(r1.text, "= 2\n\n")
  assert_eq(r1.quit, false)
  assert_eq(e.handle("name").text, "= moonbaduk\n\n")
  assert_eq(e.handle("version").text, "= 0.1.0\n\n")
  assert_eq(e.handle("known_command play").text, "= true\n\n")
  assert_eq(e.handle("known_command teleport").text, "= false\n\n")
  // list_commands mentions the core commands
  let list = e.handle("list_commands").text
  assert_eq(list.contains("genmove"), true)
  assert_eq(list.contains("showboard"), true)
}

///|
test "gtp: command ids are echoed" {
  let e = @gtp.GtpEngine::new("m", "0")
  assert_eq(e.handle("12 name").text, "=12 m\n\n")
  assert_eq(e.handle("7 nonsense").text, "?7 unknown command\n\n")
  // empty and whitespace-only lines produce no output
  assert_eq(e.handle("").text, "")
  assert_eq(e.handle("   ").text, "")
}

///|
test "gtp: boardsize, komi and clear_board" {
  let e = @gtp.GtpEngine::new("m", "0")
  assert_eq(e.handle("boardsize 9").text, "=\n\n")
  assert_eq(e.handle("komi 5.5").text, "=\n\n")
  // an out-of-range size is rejected
  assert_eq(e.handle("boardsize 1").text.has_prefix("? "), true)
  assert_eq(e.handle("boardsize abc").text.has_prefix("? "), true)
  // non-integer komi is rejected
  assert_eq(e.handle("komi xyz").text.has_prefix("? "), true)
  // clear_board resets to 9x9 again
  let _ = e.handle("boardsize 9")
  let _ = e.handle("play black a1")
  let _ = e.handle("clear_board")
  assert_eq(e.board().get(8, 0), @moonbaduk.Empty)
}

///|
test "gtp: play with GTP vertices (letter i skipped)" {
  let e = @gtp.GtpEngine::new("m", "0")
  let _ = e.handle("boardsize 9")
  // GTP a1 = bottom-left = (row 8, col 0); c3 = (6, 2)
  assert_eq(e.handle("play B a1").text, "=\n\n")
  assert_eq(e.handle("play w c3").text, "=\n\n")
  assert_eq(e.board().get(8, 0), @moonbaduk.Black)
  assert_eq(e.board().get(6, 2), @moonbaduk.White)
  // occupied point is rejected with the engine's message
  assert_eq(e.handle("play b a1").text, "? point is occupied\n\n")
  // off-board vertex is rejected
  assert_eq(e.handle("play b z9").text.has_prefix("? "), true)
  // pass is accepted
  assert_eq(e.handle("play b pass").text, "=\n\n")
  assert_eq(e.handle("play w pass").text, "=\n\n")
  // two passes end the game; area score with komi 7.5 -> W+7.5
  assert_eq(e.handle("final_score").text, "= W+7.5\n\n")
}

///|
test "gtp: capture through play and undo" {
  let e = @gtp.GtpEngine::new("m", "0")
  let _ = e.handle("boardsize 5")
  // W corner stone at a5 (top-left, row 0 col 0), B surrounds it
  let _ = e.handle("play white a5")
  let _ = e.handle("play black b5")
  let _ = e.handle("play black a4")
  // replay shows the capture took effect
  assert_eq(e.board().get(0, 0), @moonbaduk.Empty)
  // undo removes the capturing stone (b5 stays), then b5
  let _ = e.handle("undo")
  assert_eq(e.board().get(0, 0), @moonbaduk.White)
  assert_eq(e.board().get(0, 1), @moonbaduk.Black)
  let _ = e.handle("undo")
  assert_eq(e.board().get(0, 0), @moonbaduk.White)
  assert_eq(e.board().get(0, 1), @moonbaduk.Empty)
  let _ = e.handle("undo")
  assert_eq(e.board().get(0, 0), @moonbaduk.Empty)
  // undoing past the start is an error
  assert_eq(e.handle("undo").text, "? cannot undo\n\n")
}

///|
test "gtp: genmove is deterministic and updates the board" {
  let e = @gtp.GtpEngine::new("m", "0")
  let _ = e.handle("boardsize 9")
  let r = e.handle("genmove black")
  assert_eq(r.text.has_prefix("= "), true)
  // the reference mover takes the first legal point in scan order:
  // top-left corner in GTP naming = A9
  assert_eq(r.text, "= A9\n\n")
  assert_eq(e.board().get(0, 0), @moonbaduk.Black)
  // when no legal move remains, genmove passes (here: both empty points
  // of the 2x2 board would be suicide for black)
  let _ = e.handle("clear_board")
  let _ = e.handle("boardsize 2")
  let _ = e.handle("play b a2")
  let _ = e.handle("play w b2")
  let _ = e.handle("play w a1") // captures the black stone
  assert_eq(e.handle("genmove black").text, "= pass\n\n")
}

///|
test "gtp: showboard and malformed input never panic" {
  let e = @gtp.GtpEngine::new("m", "0")
  let _ = e.handle("boardsize 3")
  let _ = e.handle("play b a3")
  let shown = e.handle("showboard").text
  assert_eq(shown.contains("X"), true)
  // malformed inputs all produce ? responses, no crash
  assert_eq(e.handle("play").text.has_prefix("? "), true)
  assert_eq(e.handle("play b").text.has_prefix("? "), true)
  assert_eq(e.handle("komi").text.has_prefix("? "), true)
  assert_eq(e.handle("boardsize").text.has_prefix("? "), true)
  assert_eq(e.handle("genmove").text.has_prefix("? "), true)
  assert_eq(e.handle("known_command").text.has_prefix("? "), true)
  assert_eq(e.handle("play b j10").text.has_prefix("? "), true)
}

///|
test "gtp: quit signals shutdown" {
  let e = @gtp.GtpEngine::new("m", "0")
  assert_eq(e.quit_requested(), false)
  let r = e.handle("quit")
  assert_eq(r.quit, true)
  assert_eq(e.quit_requested(), true)
}

///|
test "gtp: a whole session replays a small game" {
  let e = @gtp.GtpEngine::new("moonbaduk-ref", "0.1.0")
  let script = [
    "boardsize 9", "komi 0.5", "play b e5", "play w e4", "play b e6",
    "play w d5", "list_commands", "undo", "undo", "undo", "final_score",
    "protocol_version", "quit",
  ]
  let mut last = ""
  for cmd in script {
    last = e.handle(cmd).text
  }
  assert_eq(last, "=\n\n")
  assert_eq(e.quit_requested(), true)
}
