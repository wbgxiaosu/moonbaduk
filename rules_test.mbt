// Blackbox tests for the rules engine. Run `moon test`.

///|
test "board: neighbors, clamping and roundtrip" {
  let b = @moonbaduk.Board::new(9)
  assert_eq(b.size, 9)
  assert_eq(b.neighbors(b.idx(4, 4)).length(), 4)
  assert_eq(b.neighbors(b.idx(0, 0)).length(), 2)
  assert_eq(b.neighbors(b.idx(0, 4)).length(), 3)
  assert_eq(@moonbaduk.Board::new(99).size, 26)
  assert_eq(@moonbaduk.Board::new(1).size, 2)
  let b2 = @moonbaduk.Board::new(13)
  b2.set(5, 7, @moonbaduk.White)
  assert_eq(b2.get(5, 7), @moonbaduk.White)
  assert_eq(b2.row_of(b2.idx(5, 7)), 5)
  assert_eq(b2.col_of(b2.idx(5, 7)), 7)
}

///|
test "board: group and liberties" {
  let b = @moonbaduk.Board::new(9)
  b.set(4, 4, @moonbaduk.Black)
  let g = b.group_at(b.idx(4, 4))
  assert_eq(g.stones.length(), 1)
  assert_eq(g.liberties.length(), 4)
  b.set(0, 0, @moonbaduk.White)
  assert_eq(b.group_at(b.idx(0, 0)).liberties.length(), 2)
  b.set(4, 5, @moonbaduk.Black)
  let g2 = b.group_at(b.idx(4, 4))
  assert_eq(g2.stones.length(), 2)
  assert_eq(g2.liberties.length(), 6)
  assert_eq(b.group_at(b.idx(8, 8)).stones.length(), 0)
}

///|
test "rules: bounds and occupancy errors" {
  let g = @moonbaduk.Game::new(5, 0.0)
  assert_eq(g.play(5, 0), Err(@moonbaduk.OutOfBounds))
  assert_eq(g.play(-1, 2), Err(@moonbaduk.OutOfBounds))
  let _ = g.play(2, 2)
  assert_eq(g.play(2, 2), Err(@moonbaduk.Occupied))
  assert_eq(
    g.play_stone(@moonbaduk.Empty, 0, 0),
    Err(@moonbaduk.Occupied),
  )
}

///|
test "rules: single stone capture on the edge" {
  let g = @moonbaduk.Game::new(9, 0.0)
  let _ = g.play_stone(@moonbaduk.White, 0, 0)
  let _ = g.play_stone(@moonbaduk.Black, 0, 1)
  let _ = g.play_stone(@moonbaduk.White, 8, 8)
  assert_eq(g.play_stone(@moonbaduk.Black, 1, 0), Ok(1))
  assert_eq(g.board().get(0, 0), @moonbaduk.Empty)
  let (cb, cw) = g.captures()
  assert_eq(cb, 1)
  assert_eq(cw, 0)
}

///|
test "rules: group capture" {
  let g = @moonbaduk.Game::new(9, 0.0)
  let _ = g.play_stone(@moonbaduk.White, 0, 0)
  let _ = g.play_stone(@moonbaduk.Black, 5, 5)
  let _ = g.play_stone(@moonbaduk.White, 0, 1)
  let _ = g.play_stone(@moonbaduk.Black, 1, 0)
  let _ = g.play_stone(@moonbaduk.Black, 0, 2) // seal the last outside liberty
  assert_eq(g.play_stone(@moonbaduk.Black, 1, 1), Ok(2))
  assert_eq(g.board().get(0, 0), @moonbaduk.Empty)
  assert_eq(g.board().get(0, 1), @moonbaduk.Empty)
}

///|
test "rules: capture beats suicide (killing stone needs no outside liberty)" {
  let g = @moonbaduk.Game::new(5, 0.0)
  let setup = [
    (@moonbaduk.White, 0, 1),
    (@moonbaduk.White, 1, 1),
    (@moonbaduk.White, 2, 1),
    (@moonbaduk.Black, 0, 0),
    (@moonbaduk.Black, 1, 0),
    (@moonbaduk.Black, 0, 2),
    (@moonbaduk.Black, 1, 2),
    (@moonbaduk.Black, 2, 2),
    (@moonbaduk.Black, 3, 1),
    (@moonbaduk.Black, 3, 0),
  ]
  for s in setup {
    let (stone, r, c) = s
    g.setup_stone(r, c, stone)
  }
  // the B chain has no liberty of its own: the move at (2,0) is legal only
  // because it captures the three-stone W group
  assert_eq(g.play_stone(@moonbaduk.Black, 2, 0), Ok(3))
  assert_eq(g.board().get(1, 1), @moonbaduk.Empty)
  assert_eq(g.board().get(2, 0), @moonbaduk.Black)
}

///|
test "rules: suicide without capture is rejected" {
  let g = @moonbaduk.Game::new(5, 0.0)
  let setup = [
    (@moonbaduk.Black, 1, 0),
    (@moonbaduk.White, 1, 1),
    (@moonbaduk.White, 2, 1),
    (@moonbaduk.Black, 3, 0),
    (@moonbaduk.White, 3, 1),
    (@moonbaduk.White, 0, 0),
    (@moonbaduk.Black, 4, 0),
    (@moonbaduk.White, 4, 1),
  ]
  for s in setup {
    let (stone, r, c) = s
    g.setup_stone(r, c, stone)
  }
  // (2,0) joins the B chain (1,0)-(3,0) which has no liberty, and captures
  // nothing: the W wall (1,1)-(3,1) still has liberties on the right
  assert_eq(g.play_stone(@moonbaduk.Black, 2, 0), Err(@moonbaduk.Suicide))
}

///|
test "rules: simple ko blocks immediate recapture" {
  let g = @moonbaduk.Game::new(9, 0.0)
  let setup = [
    (@moonbaduk.White, 0, 1),
    (@moonbaduk.White, 2, 1),
    (@moonbaduk.White, 1, 0),
    (@moonbaduk.Black, 0, 2),
    (@moonbaduk.Black, 2, 2),
    (@moonbaduk.Black, 1, 3),
  ]
  for s in setup {
    let (stone, r, c) = s
    g.setup_stone(r, c, stone)
  }
  // B takes the ko at (1,2) with (1,1)
  assert_eq(g.play_stone(@moonbaduk.Black, 1, 1), Ok(0))
  // W immediately recaptures, capturing the lone B stone
  assert_eq(g.play_stone(@moonbaduk.White, 1, 2), Ok(1))
  // B is forbidden to recapture right away
  assert_eq(g.play_stone(@moonbaduk.Black, 1, 1), Err(@moonbaduk.KoViolation))
  assert_eq(g.ko_point(), Some((1, 1)))
}

///|
test "rules: ko recapture is legal again after a ko threat exchange" {
  let g = @moonbaduk.Game::new(9, 0.0)
  let setup = [
    (@moonbaduk.White, 0, 1),
    (@moonbaduk.White, 2, 1),
    (@moonbaduk.White, 1, 0),
    (@moonbaduk.Black, 0, 2),
    (@moonbaduk.Black, 2, 2),
    (@moonbaduk.Black, 1, 3),
  ]
  for s in setup {
    let (stone, r, c) = s
    g.setup_stone(r, c, stone)
  }
  let _ = g.play_stone(@moonbaduk.Black, 1, 1) // B takes ko
  let _ = g.play_stone(@moonbaduk.White, 1, 2) // W recaptures
  // B ko threat far away, W answers
  let _ = g.play_stone(@moonbaduk.Black, 8, 8)
  let _ = g.play_stone(@moonbaduk.White, 7, 7)
  // B recaptures legally (the threat stones make the position new)
  assert_eq(g.play_stone(@moonbaduk.Black, 1, 1), Ok(1))
  // W must wait again
  assert_eq(
    g.play_stone(@moonbaduk.White, 1, 2),
    Err(@moonbaduk.KoViolation),
  )
}

///|
test "rules: positional superko blocks exact board repetition" {
  let g = @moonbaduk.Game::new(5, 0.0)
  let setup = [
    (@moonbaduk.White, 0, 1),
    (@moonbaduk.White, 2, 1),
    (@moonbaduk.White, 1, 0),
    (@moonbaduk.Black, 0, 2),
    (@moonbaduk.Black, 2, 2),
    (@moonbaduk.Black, 1, 3),
  ]
  for s in setup {
    let (stone, r, c) = s
    g.setup_stone(r, c, stone)
  }
  let _ = g.play_stone(@moonbaduk.Black, 1, 1) // B takes ko
  let _ = g.play_stone(@moonbaduk.White, 1, 2) // W recaptures: position P2
  let key_p2 = g.board().position_key()
  // roll back to right before the recapture and pre-register P2 as if the
  // game had passed through it before
  let _ = g.undo()
  g.set_history([key_p2])
  assert_eq(
    g.play_stone(@moonbaduk.White, 1, 2),
    Err(@moonbaduk.SuperkoViolation),
  )
}

///|
test "rules: pass, two passes end the game and undo restores state" {
  let g = @moonbaduk.Game::new(9, 0.5)
  assert_eq(g.play(3, 3), Ok(0))
  assert_eq(g.turn(), @moonbaduk.White)
  g.play_pass(@moonbaduk.White)
  assert_eq(g.consecutive_passes(), 1)
  assert_eq(g.is_over(), false)
  g.play_pass(@moonbaduk.Black)
  assert_eq(g.is_over(), true)
  assert_eq(g.undo(), true)
  assert_eq(g.is_over(), false)
  assert_eq(g.consecutive_passes(), 1)
  assert_eq(g.turn(), @moonbaduk.Black)
  g.play_pass(@moonbaduk.Black)
  assert_eq(g.play(4, 4), Err(@moonbaduk.GameOver))
}

///|
test "rules: area scoring counts stones, territory and komi" {
  let g = @moonbaduk.Game::new(5, 0.5)
  let _ = g.play_stone(@moonbaduk.Black, 0, 1)
  let _ = g.play_stone(@moonbaduk.White, 4, 4)
  let _ = g.play_stone(@moonbaduk.Black, 1, 0)
  let _ = g.play_stone(@moonbaduk.White, 4, 3)
  let _ = g.play_stone(@moonbaduk.Black, 1, 1)
  let _ = g.play_stone(@moonbaduk.White, 3, 4)
  g.play_pass(@moonbaduk.Black)
  g.play_pass(@moonbaduk.White)
  // (0,0) is enclosed by black alone -> +1; the big open area borders both
  // colors -> neutral. Black 3+1=4, White 3 stones + 0.5 komi = 3.5.
  assert_eq(g.final_score(), "B+0.5")
  g.set_komi(2.5)
  assert_eq(g.final_score(), "W+1.5")
  g.set_komi(1.0)
  assert_eq(g.final_score(), "0")
  // scoring before the game ends returns void
  let _ = g.undo()
  assert_eq(g.final_score(), "void")
}

///|
test "rules: legal_points excludes occupied points and ends with game over" {
  let g = @moonbaduk.Game::new(4, 0.0)
  let _ = g.play_stone(@moonbaduk.Black, 0, 0)
  assert_eq(g.legal_points(@moonbaduk.White).length(), 4 * 4 - 1)
  g.play_pass(@moonbaduk.White)
  g.play_pass(@moonbaduk.Black)
  assert_eq(g.legal_points(@moonbaduk.White).length(), 0)
}

///|
test "rules: out-of-turn play flips the turn" {
  let g = @moonbaduk.Game::new(9, 0.0)
  let _ = g.play(2, 2) // Black
  assert_eq(g.play_stone(@moonbaduk.Black, 3, 3), Ok(0))
  assert_eq(g.turn(), @moonbaduk.White)
}

///|
test "rules: undo restores board and captures" {
  let g = @moonbaduk.Game::new(9, 0.0)
  let _ = g.play_stone(@moonbaduk.White, 0, 0)
  let _ = g.play_stone(@moonbaduk.Black, 0, 1)
  let _ = g.play_stone(@moonbaduk.White, 8, 8)
  let _ = g.play_stone(@moonbaduk.Black, 1, 0) // captures (0,0)
  assert_eq(g.captures().0, 1)
  let _ = g.undo()
  assert_eq(g.captures().0, 0)
  assert_eq(g.board().get(0, 0), @moonbaduk.White)
  assert_eq(g.turn(), @moonbaduk.Black)
}
