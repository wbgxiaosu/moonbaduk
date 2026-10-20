///|
/// Example binary demonstrating the moonbaduk library components.
/// This is a usage example, not a product: the deliverable is the
/// reusable library (board / rules / sgf / gtp packages).
fn main {
  // 1. the rules engine: play a capture on a 9x9 board
  let g = @moonbaduk.Game::new(9, 7.5)
  let _ = g.play_stone(@moonbaduk.White, 0, 0)
  let _ = g.play_stone(@moonbaduk.Black, 0, 1)
  let _ = g.play_stone(@moonbaduk.Black, 1, 0)
  println("board after a corner capture:")
  println(g.board().render())
  let (cb, cw) = g.captures()
  println("captures (black, white): \{cb}, \{cw}")
  // 2. the SGF pipeline: serialize -> parse -> replay
  let record = "(;GM[1]FF[4]SZ[9]KM[7.5];W[aa];B[ab];B[ba])"
  match @sgf.parse_sgf_one(record) {
    Ok(tree) =>
      match tree.replay() {
        Ok(rep) => {
          let same = rep.game.board().position_key() == g.board().position_key()
          println("replayed \{rep.moves} moves, \{rep.warnings.length()} warnings, key match: \{same}")
        }
        Err(msg) => println("replay failed: \{msg}")
      }
    Err(e) => println("parse failed: \{e.message()}")
  }
  // 3. the GTP engine: feed commands, get responses
  let e : @gtp.GtpEngine = @gtp.GtpEngine::new("moonbaduk", "0.1.0")
  let r1 = e.handle("boardsize 9")
  let r2 = e.handle("genmove black")
  println(r1.text + r2.text)
}
