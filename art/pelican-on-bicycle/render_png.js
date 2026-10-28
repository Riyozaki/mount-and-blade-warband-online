// Render an SVG to PNG with resvg (no system cairo / browser needed).
// usage: node render_png.js <in.svg> <out.png> [scale]
const fs = require("fs");

let Resvg;
try {
  ({ Resvg } = require("@resvg/resvg-js"));
} catch {
  // fallback: sandbox-local install outside the repo
  ({ Resvg } = require("/home/user/tools/node_modules/@resvg/resvg-js"));
}

const [input, output, scaleArg] = process.argv.slice(2);
const scale = parseFloat(scaleArg || "1");
const svg = fs.readFileSync(input, "utf8");

const resvg = new Resvg(svg, {
  fitTo: { mode: "zoom", value: scale },
  background: "rgba(0, 0, 0, 0)",
  // NB: passing textRendering/imageRendering here makes resvg-js silently
  // ignore fitTo, so leave the rendering hints at their defaults.
});

const png = resvg.render().asPng();
fs.writeFileSync(output, png);
console.log(`wrote ${output} (${png.length.toLocaleString()} bytes)`);
