// Blackbox tests for the SGF package. Run `moon test`.

///|
test "sgf: parse a minimal record" {
  let r = @sgf.parse_sgf_one("(;GM[1]FF[4]SZ[19]KM[6.5];B[pd];W[dp])")
  assert_true(r is Ok(_))
  let tree = r.unwrap()
  let root = tree.root()
  assert_eq(root.get("GM"), Some("1"))
  assert_eq(root.get("SZ"), Some("19"))
  assert_eq(root.get("KM"), Some("6.5"))
  assert_eq(tree.main_line().length(), 3)
}

///|
test "sgf: parse variations and roundtrip" {
  let src = "(;GM[1]FF[4]SZ[9];B[cc];W[gc](;B[cg](;C[try \\] it])(;B[aa]))(;B[dd]))"
  let tree = @sgf.parse_sgf_one(src).unwrap()
  assert_eq(tree.children.length(), 2)
  let rt = tree.to_sgf()
  let tree2 = @sgf.parse_sgf_one(rt).unwrap()
  assert_eq(tree2.to_sgf(), rt)
  // the escaped bracket survived the roundtrip (value is "try ] it")
  assert_eq(
    tree2.children[0].children[0].root().get("C"),
    Some("try ] it"),
  )
}

///|
test "sgf: escaped newline and lowercase property ids" {
  // the C value contains a backslash followed by a real newline (soft
  // line break, removed per FF[4])
  let src = "(;gm[1]ff[4]sz[4];c[first\\" + "\nline];b[aa])"
  let tree = @sgf.parse_sgf_one(src).unwrap()
  assert_eq(tree.root().get("GM"), Some("1"))
  let node = tree.main_line()[1]
  assert_eq(node.get("C"), Some("firstline"))
  assert_eq(tree.main_line()[2].get("B"), Some("aa"))
}

///|
test "sgf: escaped crlf and literal escaped chars" {
  // CRLF soft break is removed entirely; \: and \\ become : and \
  let src = "(;GM[1];c[a\\" + "\r\nb]d[d\\:e]f[f\\\\g])"
  let tree = @sgf.parse_sgf_one(src).unwrap()
  let node = tree.main_line()[1]
  assert_eq(node.get("C"), Some("ab"))
  assert_eq(node.get("D"), Some("d:e"))
  assert_eq(node.get("F"), Some("f\\g"))
}

///|
test "sgf: malformed input is rejected" {
  assert_true(@sgf.parse_sgf_one("(;GM[1") is Err(_))
  assert_true(@sgf.parse_sgf_one("") is Err(_))
  assert_true(@sgf.parse_sgf_one(";B[aa]") is Err(_))
}

///|
test "sgf: replay a short game and verify captures" {
  // W corner stone at a1 gets captured by B (a2, b1)
  let src = "(;GM[1]FF[4]SZ[9]KM[0.5];B[gc];W[aa];B[ba];W[gg];B[ab])"
  let rep = @sgf.parse_sgf_one(src).unwrap().replay().unwrap()
  assert_eq(rep.moves, 5)
  assert_eq(rep.warnings.length(), 0)
  assert_eq(rep.game.board().get(0, 0), @moonbaduk.Empty)
  let (cb, cw) = rep.game.captures()
  assert_eq(cb, 1)
  assert_eq(cw, 0)
  assert_eq(rep.game.turn(), @moonbaduk.White)
}

///|
test "sgf: replay honours SZ, KM, handicap stones and passes" {
  // 13x13, komi 0, two AB stones, then a pass each (tt is a pass)
  let src = "(;GM[1]FF[4]SZ[13]KM[0]HA[2]AB[dd][jj];B[tt];W[tt])"
  let rep = @sgf.parse_sgf_one(src).unwrap().replay().unwrap()
  assert_eq(rep.game.size(), 13)
  assert_eq(rep.game.komi(), 0.0)
  assert_eq(rep.game.board().get(3, 3), @moonbaduk.Black)
  assert_eq(rep.game.board().get(9, 9), @moonbaduk.Black)
  assert_eq(rep.moves, 0)
  assert_eq(rep.game.is_over(), true)
}

///|
test "sgf: replay collects illegal moves as warnings" {
  // W plays on the same point twice
  let src = "(;GM[1]FF[4]SZ[9];B[dd];W[dd];W[dd])"
  let rep = @sgf.parse_sgf_one(src).unwrap().replay().unwrap()
  assert_eq(rep.moves, 3)
  assert_eq(rep.warnings.length(), 2)
  assert_eq(rep.game.board().get(3, 3), @moonbaduk.Black)
}

///|
test "sgf: long self-play game survives a write-parse-replay roundtrip" {
  // Play a long deterministic game on 19x19 (both sides always take the
  // first legal point in scan order), record every move, serialize the
  // record to SGF by hand, then replay it and require the final position,
  // capture counts and move count to match the original game.
  let g = @moonbaduk.Game::new(19, 7.5)
  let moves : Array[(String, String)] = [] // (color letter, SGF coord)
  let mut stone_moves = 0
  for round in 0..<170 {
    if g.is_over() {
      break
    }
    let color = if round % 2 == 0 {
      @moonbaduk.Black
    } else {
      @moonbaduk.White
    }
    let letter = if color is @moonbaduk.Black { "B" } else { "W" }
    let pts = g.legal_points(color)
    if pts.length() > 0 {
      let (r, c) = pts[0]
      let _ = g.play_stone(color, r, c)
      stone_moves += 1
      let letters : Array[Char] = []
      for ch in "abcdefghijklmnopqrstuvwxyz" {
        letters.push(ch)
      }
      let cb = StringBuilder()
      cb.write_char(letters[c])
      cb.write_char(letters[r])
      moves.push((letter, cb.to_string()))
    } else {
      g.play_pass(color)
      moves.push((letter, ""))
    }
  }
  assert_true(moves.length() > 100)
  // serialize
  let buf = StringBuilder()
  buf.write_string("(;GM[1]FF[4]SZ[19]KM[7.5]")
  for m in moves {
    let (letter, coord) = m
    buf.write_string(";\{letter}[\{coord}]")
  }
  buf.write_string(")")
  let sgf = buf.to_string()
  // read back and replay
  let rep = @sgf.parse_sgf_one(sgf).unwrap().replay().unwrap()
  if rep.warnings.length() > 0 {
    let w = StringBuilder()
    for x in rep.warnings {
      w.write_string(x)
      w.write_string("; ")
    }
    fail("warnings: \{w.to_string()}")
  }
  assert_eq(rep.moves, stone_moves)
  assert_eq(rep.game.board().position_key(), g.board().position_key())
  assert_eq(rep.game.captures().0, g.captures().0)
  assert_eq(rep.game.captures().1, g.captures().1)
}
