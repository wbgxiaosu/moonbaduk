///|
/// Escapes an SGF property value: `]` and `\` get a backslash.
fn escape_value(v : String) -> String {
  let buf = StringBuilder()
  for c in v {
    if c == ']' || c == '\\' {
      buf.write_char('\\')
    }
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// Serializes one node (without the leading `;`).
fn SgfNode::write(self : SgfNode, buf : StringBuilder) -> Unit {
  for p in self.props {
    buf.write_string(p.id)
    for v in p.values {
      buf.write_char('[')
      buf.write_string(escape_value(v))
      buf.write_char(']')
    }
  }
}

///|
/// Serializes the tree in standard SGF form:
/// `(;root;main-line...(;variation...)(;variation...))`.
pub fn SgfTree::to_sgf(self : SgfTree) -> String {
  let buf = StringBuilder()
  buf.write_char('(')
  for n in self.nodes {
    buf.write_char(';')
    n.write(buf)
  }
  for c in self.children {
    buf.write_string(c.to_sgf())
  }
  buf.write_char(')')
  buf.to_string()
}

///|
/// Builds a node from (id, values) pairs, for hand-constructed trees.
pub fn SgfNode::of(props : Array[(String, Array[String])]) -> SgfNode {
  let ps : Array[SgfProp] = []
  for p in props {
    let (id, values) = p
    ps.push({ id, values })
  }
  { props: ps }
}

///|
/// Sets (replaces) a property on the node.
pub fn SgfNode::set(self : SgfNode, id : String, values : Array[String]) -> Unit {
  for p in self.props {
    if p.id == id {
      p.values = values
      return
    }
  }
  self.props.push({ id, values })
}

///|
/// The first node of the tree (the root). Assumes a non-empty tree.
pub fn SgfTree::root(self : SgfTree) -> SgfNode {
  self.nodes[0]
}

///|
/// Walks the main line (first variation at every branch) and returns the
/// node sequence.
pub fn SgfTree::main_line(self : SgfTree) -> Array[SgfNode] {
  let acc : Array[SgfNode] = []
  let mut cur : SgfTree? = Some(self)
  while true {
    match cur {
      Some(t) => {
        for n in t.nodes {
          acc.push(n)
        }
        cur = t.children.get(0)
      }
      None => break
    }
  }
  acc
}
