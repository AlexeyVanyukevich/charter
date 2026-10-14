---
paths:
  - "tests/ui/**"
---
# Browser journeys in Playwright

Find by role with `page.getByRole('button', { name: 'Save' })`, and scan with
`@axe-core/playwright`:

    const { violations } = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze()
    expect(violations).toEqual([])

`WCAG_TAGS` is one shared constant. A known failure is left out with `.exclude(selector)`.
