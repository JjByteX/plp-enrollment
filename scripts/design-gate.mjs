// Design gate. Run: node scripts/design-gate.mjs
// Fails when UI code hardcodes colors, fonts, or spacing/radius values
// instead of using styles/tokens.ts (ux-ui-guidelines.md).
// Scans app/, features/ and components/. styles/ is where tokens live, so it is skipped.
import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, extname } from "node:path";

const ROOTS = ["app", "features", "components"];
const EXT = new Set([".ts", ".tsx", ".css"]);

const RULES = [
  { name: "hardcoded color", re: /#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?)\(/ },
  { name: "hardcoded font-family", re: /font-?[fF]amily\s*:\s*['"`]?[A-Za-z]/ },
  {
    name: "hardcoded spacing/radius value",
    re: /\b(?:padding|margin|gap|borderRadius|border-radius)[A-Za-z]*\s*:\s*['"`]?\d+(?:\.\d+)?(?:px|rem|em)?['"`]?\s*[,;}\n]/,
  },
];

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (EXT.has(extname(p))) out.push(p);
  }
  return out;
}

const problems = [];
for (const root of ROOTS.filter(existsSync)) {
  for (const file of walk(root)) {
    readFileSync(file, "utf8").split("\n").forEach((line, i) => {
      if (/^\s*(\/\/|\*|\/\*)/.test(line)) return; // comments
      for (const r of RULES) if (r.re.test(line)) problems.push(`${file}:${i + 1}  ${r.name}: ${line.trim()}`);
    });
  }
}

if (problems.length) {
  console.error(`Design gate failed (${problems.length}). Use styles/tokens.ts instead:\n`);
  console.error(problems.join("\n"));
  process.exit(1);
}
console.log("Design gate passed.");
