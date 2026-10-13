// Just enough JSX typing for the type-aware rules to see what an attribute expects, without
// installing React into the fixture.
declare namespace JSX {
  interface IntrinsicElements {
    button: { onClick?: () => void }
    li: { key?: number }
  }
}
