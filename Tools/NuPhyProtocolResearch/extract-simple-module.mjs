import fs from "node:fs";

function extractModule(source, id) {
  const marker = `${id}:function`;
  const start = source.indexOf(marker);
  if (start < 0) throw new Error(`Module ${id} not found`);
  const functionStart = source.indexOf("function", start);
  const braceStart = source.indexOf("{", functionStart);
  let depth = 0;
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;
  for (let index = braceStart; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (character === "\n") lineComment = false;
      continue;
    }
    if (blockComment) {
      if (character === "*" && next === "/") {
        blockComment = false;
        index += 1;
      }
      continue;
    }
    if (quote) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === "/" && next === "/") {
      lineComment = true;
      index += 1;
      continue;
    }
    if (character === "/" && next === "*") {
      blockComment = true;
      index += 1;
      continue;
    }
    if (["\"", "'", "`"].includes(character)) {
      quote = character;
      continue;
    }
    if (character === "{") depth += 1;
    if (character === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(functionStart, index + 1);
    }
  }
  throw new Error(`Module ${id} did not terminate`);
}

const [bundlePath, moduleID = "40877"] = process.argv.slice(2);
if (!bundlePath) throw new Error("Usage: node extract-simple-module.mjs <bundle.js> [module-id]");
const source = fs.readFileSync(bundlePath, "utf8");
const moduleFactory = Function(`return (${extractModule(source, moduleID)})`)();
const exported = {};
const webpackRequire = dependency => {
  throw new Error(`Unexpected dependency ${dependency}`);
};
webpackRequire.d = (target, definitions) => {
  for (const [key, getter] of Object.entries(definitions)) {
    Object.defineProperty(target, key, { enumerable: true, get: getter });
  }
};
moduleFactory({ exports: exported }, exported, webpackRequire);
console.log(JSON.stringify(exported, null, 2));
