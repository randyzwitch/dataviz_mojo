<!--
What changed and why. Link the issue it closes: "Closes #123".
If it changes what a chart draws, say so plainly and show it.
-->

## Checks

See [CONTRIBUTING.md](../blob/main/CONTRIBUTING.md) for what each one covers.

- [ ] `pixi run format`
- [ ] `pixi run test-changed` (or `pixi run test` for shared rendering, encoding, scale, or layout changes)
- [ ] `pixi run example` and `pixi run example-quickstart`, if a docstring example or the quickstart changed
- [ ] `pixi run docs`, if anything under `docs/` or a public docstring changed

## Rendered output

<!--
Delete this section if no rendered output moved.

`tests/output_digest.txt` is the gate. If it changed, `pixi run digest-update`
regenerates it -- read the diff before committing it, and say here which
figures moved and why that is correct.
-->
