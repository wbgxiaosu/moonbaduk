///|
/// One SGF property: an identifier (e.g. `B`, `KM`, `AB`) and its values.
pub struct SgfProp {
  /// Uppercased property identifier.
  id : String
  /// Raw (unescaped) values.
  mut values : Array[String]
} derive(Debug)

///|
pub extend SgfProp with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// One SGF node: a sequence of properties, written after a `;`.
pub struct SgfNode {
  props : Array[SgfProp]
} derive(Debug)

///|
pub extend SgfNode with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A game tree: a main sequence of nodes plus zero or more child trees
/// (variations).
pub struct SgfTree {
  nodes : Array[SgfNode]
  children : Array[SgfTree]
} derive(Debug)

///|
pub extend SgfTree with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// SGF parsing failure with a byte-offset-ish character position.
pub(all) enum SgfError {
  UnexpectedEof
  UnexpectedChar(Int, Char)
  BadEscape(Int)
} derive(Eq, Debug)

///|
pub extend SgfError with Eq::{equal, not_equal}

///|
pub extend SgfError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn SgfError::message(self : SgfError) -> String {
  match self {
    UnexpectedEof => "unexpected end of input"
    UnexpectedChar(pos, ch) => "unexpected character '\\\{ch}' at offset \{pos}"
    BadEscape(pos) => "dangling escape at offset \{pos}"
  }
}

///|
priv struct Parser {
  src : Array[Char]
  mut pos : Int
}

///|
/// Parses an SGF collection: one or more game trees, e.g. a whole file.
pub fn parse_sgf(src : String) -> Result[Array[SgfTree], SgfError] {
  let chars : Array[Char] = []
  for c in src {
    chars.push(c)
  }
  let p : Parser = { src: chars, pos: 0 }
  let trees : Array[SgfTree] = []
  while true {
    p.skip_ws()
    if p.pos >= p.src.length() {
      break
    }
    match p.parse_tree() {
      Ok(t) => trees.push(t)
      Err(e) => return Err(e)
    }
  }
  if trees.length() == 0 {
    return Err(UnexpectedEof)
  }
  Ok(trees)
}

///|
/// Convenience: parses the first game tree of a collection.
pub fn parse_sgf_one(src : String) -> Result[SgfTree, SgfError] {
  match parse_sgf(src) {
    Ok(trees) =>
      match trees.get(0) {
        Some(t) => Ok(t)
        None => Err(UnexpectedEof)
      }
    Err(e) => Err(e)
  }
}

///|
fn Parser::skip_ws(self : Parser) -> Unit {
  while self.pos < self.src.length() {
    match self.src[self.pos] {
      ' ' | '\t' | '\n' | '\r' => self.pos += 1
      _ => break
    }
  }
}

///|
fn Parser::peek(self : Parser) -> Char? {
  if self.pos < self.src.length() {
    Some(self.src[self.pos])
  } else {
    None
  }
}

///|
fn Parser::parse_tree(self : Parser) -> Result[SgfTree, SgfError] {
  match self.peek() {
    Some('(') => self.pos += 1
    Some(ch) => return Err(UnexpectedChar(self.pos, ch))
    None => return Err(UnexpectedEof)
  }
  let nodes : Array[SgfNode] = []
  let children : Array[SgfTree] = []
  while true {
    self.skip_ws()
    match self.peek() {
      Some(';') =>
        match self.parse_node() {
          Ok(n) => nodes.push(n)
          Err(e) => return Err(e)
        }
      Some('(') =>
        match self.parse_tree() {
          Ok(t) => children.push(t)
          Err(e) => return Err(e)
        }
      Some(')') => {
        self.pos += 1
        return Ok({ nodes, children, })
      }
      Some(ch) => return Err(UnexpectedChar(self.pos, ch))
      None => return Err(UnexpectedEof)
    }
  }
  Ok({ nodes, children, })
}

///|
fn Parser::parse_node(self : Parser) -> Result[SgfNode, SgfError] {
  self.pos += 1 // consume ';'
  let props : Array[SgfProp] = []
  while true {
    self.skip_ws()
    match self.peek() {
      Some(ch) =>
        if ch.is_alpha() {
          match self.parse_prop() {
            Ok(p) => props.push(p)
            Err(e) => return Err(e)
          }
        } else {
          return Ok({ props, })
        }
      None => return Ok({ props, })
    }
  }
  Ok({ props, })
}

///|
fn Char::is_alpha(self : Char) -> Bool {
  (self >= 'a' && self <= 'z') || (self >= 'A' && self <= 'Z')
}

///|
fn Parser::parse_prop(self : Parser) -> Result[SgfProp, SgfError] {
  let id_buf = StringBuilder()
  while true {
    match self.peek() {
      Some(ch) =>
        if ch.is_alpha() {
          id_buf.write_char(ch.to_ascii_uppercase())
          self.pos += 1
        } else {
          break
        }
      None => return Err(UnexpectedEof)
    }
  }
  let values : Array[String] = []
  while true {
    self.skip_ws()
    match self.peek() {
      Some('[') =>
        match self.parse_value() {
          Ok(v) => values.push(v)
          Err(e) => return Err(e)
        }
      _ => break
    }
  }
  if values.length() == 0 {
    // a property identifier without a value list is malformed
    return Err(UnexpectedChar(self.pos, self.src[self.pos]))
  }
  Ok({ id: id_buf.to_string(), values })
}

///|
fn Parser::parse_value(self : Parser) -> Result[String, SgfError] {
  self.pos += 1 // consume '['
  let buf = StringBuilder()
  while true {
    if self.pos >= self.src.length() {
      return Err(UnexpectedEof)
    }
    let ch = self.src[self.pos]
    if ch == ']' {
      self.pos += 1
      return Ok(buf.to_string())
    }
    if ch == '\\' {
      self.pos += 1
      if self.pos >= self.src.length() {
        return Err(BadEscape(self.pos))
      }
      let esc = self.src[self.pos]
      // FF[4]: a soft line break (escaped newline) is removed entirely —
      // including both characters of a CR LF pair; any other escaped
      // character is taken literally
      if esc == '\r' {
        self.pos += 1
        if self.pos < self.src.length() && self.src[self.pos] == '\n' {
          self.pos += 1
        }
      } else if esc == '\n' {
        self.pos += 1
      } else {
        buf.write_char(esc)
        self.pos += 1
      }
    } else {
      buf.write_char(ch)
      self.pos += 1
    }
  }
  Ok("")
}

///|
/// Returns the first value of a property, if present.
pub fn SgfNode::get(self : SgfNode, id : String) -> String? {
  for p in self.props {
    if p.id == id {
      return p.values.get(0)
    }
  }
  None
}

///|
/// Returns all values of a property (e.g. every `AB` setup stone).
pub fn SgfNode::get_all(self : SgfNode, id : String) -> Array[String] {
  for p in self.props {
    if p.id == id {
      return p.values
    }
  }
  []
}

///|
/// True when the node carries no properties at all.
pub fn SgfNode::is_empty(self : SgfNode) -> Bool {
  self.props.length() == 0
}
