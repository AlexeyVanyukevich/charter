import { expect, it } from 'vitest'

// A dataset row names itself, so a failure says which row.
const rows = [{ label: 'one', value: 1 }]

it('names its failing row', () => {
  for (const row of rows) expect(row.value, row.label).toBe(1)
})
