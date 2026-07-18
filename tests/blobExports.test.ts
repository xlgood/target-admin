import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('../src/api/admin.ts', import.meta.url), 'utf8')

test('catalog diagnostics exports request binary responses', () => {
  assert.match(
    source,
    /exportProviderCatalogFilterReasons:[\s\S]*?filter-reasons\.csv`, \{ blob: true \}/,
  )
  assert.match(
    source,
    /exportTGXInventorySyncRunFailures:[\s\S]*?failed-items\.csv`, \{ blob: true \}/,
  )
})
