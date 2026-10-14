// The html stack's own html-validate rule, charter/clickable-control: a click handler belongs on an
// element a keyboard can reach and use, as jsx-a11y holds in JSX. Spec:
// docs/superpowers/specs/2026-10-15-click-handlers-design.md.

import { createRequire } from 'node:module'
import { join } from 'node:path'

// From the project, as charter scan takes axe-core: the kit declares no dependencies, and imported
// by name html-validate would resolve beside the kit's real path, where a file: install has none.
const { Rule } = createRequire(join(process.cwd(), 'package.json'))('html-validate')

const handlers = ['onclick', 'onmousedown', 'onmouseup']
const keyHandlers = ['onkeydown', 'onkeyup']

function isControl(element) {
  switch (element.tagName) {
    case 'a':
    case 'area':
      return element.hasAttribute('href')
    case 'button':
    case 'select':
    case 'textarea':
    case 'summary':
    case 'option':
      return true
    case 'input':
      return element.getAttributeValue('type')?.toLowerCase() !== 'hidden'
    case 'audio':
    case 'video':
      return element.hasAttribute('controls')
    default:
      return false
  }
}

class ClickableControl extends Rule {
  documentation() {
    return {
      description:
        'A click handler belongs on a native control, or on an element with a role, tabindex of 0 or more and a key handler.',
    }
  }

  setup() {
    this.on('element:ready', ({ target }) => {
      if (!handlers.some((name) => target.hasAttribute(name)) || isControl(target)) return
      const role = target.getAttributeValue('role')
      if (role === null) {
        this.report(target, `<${target.tagName}> has a click handler but is not a control: use a <button>, or another native control`)
        return
      }
      const named = `<${target.tagName} role="${role}">`
      const tabindex = target.getAttributeValue('tabindex')
      if (tabindex === null || !(Number(tabindex) >= 0)) {
        this.report(target, `${named} has a click handler but no tabindex of 0 or more, so a keyboard cannot reach it`)
      } else if (!keyHandlers.some((name) => target.hasAttribute(name))) {
        this.report(target, `${named} has a click handler but no key handler, so a keyboard cannot use it`)
      }
    })
  }
}

export default { name: 'charter', rules: { 'charter/clickable-control': ClickableControl } }
