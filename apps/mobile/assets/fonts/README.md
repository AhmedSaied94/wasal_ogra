# Fonts

The app's two families, bundled so the game works offline
(`specs/008.5-m21-design-refresh/research.md` R3).

| File | Family | Licence |
| --- | --- | --- |
| `Marhey-VariableFont_wght.ttf` | `Marhey` (display: titles, buttons, numbers) | `OFL-Marhey.txt` |
| `ReadexPro-VariableFont_HEXP_wght.ttf` | `ReadexPro` (body, labels, bubbles) | `OFL-ReadexPro.txt` |

Both are variable fonts. Every type token sets the weight twice, as `fontWeight` and as a `wght`
font variation, so the axis follows the weight on every renderer.

They come from [google/fonts](https://github.com/google/fonts) at commit
`e7db6ca603fd4862010383ff17ffd6cc4ffac1c0`:

- `ofl/marhey/Marhey[wght].ttf` and `ofl/marhey/OFL.txt`;
- `ofl/readexpro/ReadexPro[HEXP,wght].ttf` and `ofl/readexpro/OFL.txt`.

Both are under the SIL Open Font License 1.1; each licence file sits beside its font.
