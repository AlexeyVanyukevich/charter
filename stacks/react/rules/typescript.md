# TypeScript in the UI

**A UI workspace resolves as a bundler does: relative imports carry no extension.**

    import { formatPrice } from '../shared/price'

A `NodeNext` workspace writes `.js` on every relative import. An import moved from here into
one must gain the extension, or that build breaks though this one type-checked a moment ago.
