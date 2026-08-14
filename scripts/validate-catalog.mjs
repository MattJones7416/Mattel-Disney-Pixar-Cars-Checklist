import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const path = resolve("PixarCarsChecklist/checked.json");
const catalog = JSON.parse(await readFile(path, "utf8"));
const required = ["name", "number", "category", "type", "link", "source", "sourceLicense"];

if (!Array.isArray(catalog) || catalog.length < 1400) {
  throw new Error(`Expected at least 1,400 catalogue entries; found ${catalog.length ?? 0}`);
}

const identifiers = new Set();
for (const [index, item] of catalog.entries()) {
  for (const field of required) {
    if (!item[field]) throw new Error(`Entry ${index} is missing ${field}`);
  }
  if (identifiers.has(item.number)) throw new Error(`Duplicate identifier: ${item.number}`);
  identifiers.add(item.number);
  if (["Planes", "Planes: Fire & Rescue"].includes(item.category)) {
    throw new Error(`Planes entry leaked into Cars catalogue: ${item.name}`);
  }
  if (!item.link.startsWith("https://dpcarswiki.com/")) throw new Error(`Unexpected source link: ${item.link}`);
}

console.log(`Validated ${catalog.length} unique released Cars die-cast variants.`);
