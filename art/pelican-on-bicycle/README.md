# Pelican on a bicycle 🚲

Vector illustration of a pelican (in a cycling helmet) riding a bicycle.

| File                    | What it is                                                        |
| ----------------------- | ----------------------------------------------------------------- |
| `pelican-on-bicycle.svg` | The artwork (hand-tuned, generated — 900×620 viewBox)             |
| `pelican-on-bicycle.png` | Raster render of the SVG (1800×1240, 2× scale)                    |
| `generate_svg.py`       | Dependency-free Python generator for the SVG (tweak & re-run)     |
| `render_png.js`         | Node script that rasterises the SVG via [`@resvg/resvg-js`][resvg] |

## Regenerate

```bash
python3 generate_svg.py                       # -> pelican-on-bicycle.svg
npm install @resvg/resvg-js                   # once, anywhere on NODE_PATH
node render_png.js pelican-on-bicycle.svg pelican-on-bicycle.png 2
```

`render_png.js` takes an optional third argument — the zoom factor
(`1` = 900×620, `2` = 1800×1240, …).

[resvg]: https://github.com/linebender/resvg
