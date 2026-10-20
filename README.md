# moonbaduk

[![CI](https://github.com/wbgxiaosu/moonbaduk/actions/workflows/ci.yml/badge.svg)](https://github.com/wbgxiaosu/moonbaduk/actions/workflows/ci.yml)

Reusable Go (weiqi/baduk) **infrastructure** for the MoonBit ecosystem: a
rules engine, an SGF game-record library and a GTP protocol engine — the
building blocks you need when you are *building* a Go GUI client, a game
record service, a teaching platform, an analysis tool or an engine
wrapper, not the finished product itself.

Licensed under Apache-2.0.

## Components

| Package | What it provides | Typical consumer |
|---|---|---|
| `moonbaduk` (root) | `Board` data structure, `Game` rules engine (Chinese rules) | any tool that must judge legality, captures, ko/superko or score |
| `moonbaduk/sgf` | SGF FF[4] parser/writer, game-tree model, replay against the rules engine | record databases, editors, converters, server-side validation |
| `moonbaduk/gtp` | Text-based GTP v2 engine over the rules engine (I/O free) | GUI frontends, bot harnesses, engine test suites |

## Usage

Add the dependency to your `moon.mod`:

```
wbgxiaosu/moonbaduk
```

### Rules engine

```moonbit
let g = @moonbaduk.Game::new(19, 7.5)       // 19x19, Chinese rules, komi 7.5
let r = g.play_stone(@moonbaduk.Black, 3, 3) // Ok(captured) or Err(PlayError)
let legal = g.legal_points(@moonbaduk.White) // ko / superko / suicide excluded
let _ = g.play_pass(@moonbaduk.White)
let score = g.final_score()                  // "B+2.5" / "W+0.5" / "0" / "void"
```

Key types: `Board` (immutable-friendly grid with flood-fill `group_at`),
`Stone`, `Game` (turn handling, captures, simple ko, positional superko,
undo, area scoring), `PlayError` (precise rejection reasons).

### SGF records

```moonbit
let tree = @sgf.parse_sgf_one("(;GM[1]FF[4]SZ[19]KM[7.5];B[pd];W[dp])")
let root_size = tree.root().get("SZ")       // Some("19")
let rep = tree.replay()                      // replayed on a fresh Game
// rep.moves, rep.warnings, rep.game
let out = tree.to_sgf()                      // writer, roundtrip-safe
```

Handles property trees with variations, escaped values (`\]`, soft line
breaks incl. CR LF), lowercase ids, `AB`/`AW` setup stones, `tt` passes
and out-of-spec data (collected as warnings instead of aborting).

### GTP engine

```moonbit
let e = @gtp.GtpEngine::new("my-client", "1.0")
let resp = e.handle("play black Q16")   // "= \n\n" or "? reason\n\n"
let resp2 = e.handle("genmove white")   // "= D4\n\n" / "= pass\n\n"
// resp.quit tells the host whether to shut down
```

Implements `protocol_version`, `name`, `version`, `known_command`,
`list_commands`, `boardsize`, `clear_board`, `komi`, `play`, `genmove`,
`undo`, `showboard`, `final_score`, `quit`, with GTP-compliant `=`/`?`
responses, optional numeric ids and tolerance for malformed input. The
engine performs no I/O, so it can sit behind a socket, a REPL or a test
harness unchanged. `genmove` is a deterministic reference mover — real
engines replace it and talk GTP to this or any other controller.

## Testing

`moon test` — 33 blackbox tests covering rules (captures, suicide,
ko/superko, scoring), SGF (parsing, escaping, roundtrips, replay) and
GTP (protocol behaviour, vertex conversion, session scripts). CI runs
the suite on all three backends (wasm/wasm-gc/native) via GitHub
Actions.

## Scope

This project deliberately implements reusable infrastructure and stops
at the protocol boundary. It does not ship a GUI, an AI or a server —
those are applications built *on top of* these components.
