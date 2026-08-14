import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const appOutput = resolve(projectRoot, "PixarCarsChecklist/checked.json");
const workerOutput = resolve(projectRoot, "catalog-worker/public/catalog.json");

const API_URL = "https://dpcarswiki.com/api.php";
const SOURCE_URL = "https://dpcarswiki.com/Special:VehicleDatabase";
const INCLUDED_TYPES = new Set([1, 2, 3, 4, 6, 7, 9, 10]);
const EXCLUDED_ORIGINS = new Set(["Planes", "Planes: Fire & Rescue"]);

function decodeEntities(input = "") {
  const named = {
    amp: "&",
    quot: '"',
    apos: "'",
    "#039": "'",
    lt: "<",
    gt: ">",
    ndash: "–",
    mdash: "—",
    nbsp: " ",
  };

  let value = String(input);
  for (let pass = 0; pass < 3; pass += 1) {
    const decoded = value.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (match, entity) => {
      const key = entity.toLowerCase();
      if (key.startsWith("#x")) return String.fromCodePoint(Number.parseInt(key.slice(2), 16));
      if (key.startsWith("#") && /^#\d+$/.test(key)) return String.fromCodePoint(Number.parseInt(key.slice(1), 10));
      return named[key] ?? match;
    });
    if (decoded === value) break;
    value = decoded;
  }
  return value;
}

function plainText(input = "") {
  return decodeEntities(input)
    .replace(/<[^>]*>/g, " ")
    .replace(/\[\[(?:[^|\]]*\|)?([^\]]+)\]\]/g, "$1")
    .replace(/'{2,}/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function sourcePageURL(page) {
  return `https://dpcarswiki.com/${encodeURIComponent(page).replaceAll("%3A", ":").replaceAll("%2F", "/")}`;
}

function imageURL(filename) {
  if (!filename) return "";
  return `https://dpcarswiki.com/Special:Redirect/file/${encodeURIComponent(filename).replaceAll("%2F", "/")}`;
}

function firstSeriesName(seriesValue, year) {
  const decoded = decodeEntities(seriesValue);
  const pageMatch = decoded.match(/\[\[([^|\]]+)/);
  const page = plainText(pageMatch?.[1] ?? "");
  if (/\(mainline series\)$/i.test(page)) return `${year} Mainline`;
  if (/\(Mini Racers\)$/i.test(page)) return `${year} Mini Racers`;
  return page || `${year} release`;
}

function cleanProductCode(value) {
  const code = plainText(value).toUpperCase();
  if (!code || ["—", "-", "TBA", "N/A", "ZZZ"].includes(code)) return "";
  return code;
}

function lineForTypes(types) {
  if ([1, 2, 3, 4].some((type) => types.has(type))) return "1:55 Die-Cast";
  if (types.has(6)) return "Collector Exclusive";
  if (types.has(7)) return "Premium / Larger Scale";
  if (types.has(9)) return "Mini Racers";
  return "Special Edition";
}

async function cargoQuery({ tables, fields, where, joinOn, orderBy }) {
  const rows = [];
  const limit = 500;

  for (let offset = 0; ; offset += limit) {
    const url = new URL(API_URL);
    url.searchParams.set("action", "cargoquery");
    url.searchParams.set("format", "json");
    url.searchParams.set("tables", tables);
    url.searchParams.set("fields", fields);
    url.searchParams.set("limit", String(limit));
    url.searchParams.set("offset", String(offset));
    if (where) url.searchParams.set("where", where);
    if (joinOn) url.searchParams.set("join_on", joinOn);
    if (orderBy) url.searchParams.set("order_by", orderBy);

    const response = await fetch(url, {
      headers: { Accept: "application/json", "User-Agent": "PixarCarsChecklistCatalog/1.0" },
    });
    if (!response.ok) throw new Error(`Cargo request failed (${response.status})`);
    const payload = await response.json();
    if (payload.error) throw new Error(payload.error.info ?? payload.error.code);

    const page = (payload.cargoquery ?? []).map((item) => item.title);
    rows.push(...page);
    if (page.length < limit) break;
  }

  return rows;
}

async function buildCatalog() {
  const [vehicles, releases] = await Promise.all([
    cargoQuery({
      tables: "Vehicles",
      fields: [
        "Vehicles._pageID=PageID",
        "Vehicles._pageName=Page",
        "Vehicles.Name=Name",
        "Vehicles.Origin=Origin",
        "Vehicles.Character_name=Character",
        "Vehicles.PhotoG=Photo",
      ].join(","),
      orderBy: "Vehicles._pageID",
    }),
    cargoQuery({
      tables: "Releases",
      fields: [
        "Releases._pageID=PageID",
        "Releases.RelID=ReleaseID",
        "Releases.Type=Type",
        "Releases.Model_Name=ModelName",
        "Releases.Year=Year",
        "Releases.Series_string=Series",
        "Releases.Format=Format",
        "Releases.Toy_Number=ToyNumber",
        "Releases.Exclusive=Exclusive",
      ].join(","),
      where: "Releases.Row_Type=3 AND Releases.Rel=1 AND Releases.Type IN (1,2,3,4,6,7,9,10)",
      orderBy: "Releases._pageID,Releases.Year,Releases.RelID",
    }),
  ]);

  const vehicleByPageID = new Map(vehicles.map((vehicle) => [String(vehicle.PageID), vehicle]));
  const releasesByPageID = new Map();

  for (const release of releases) {
    const type = Number(release.Type);
    if (!INCLUDED_TYPES.has(type)) continue;
    const key = String(release.PageID);
    const list = releasesByPageID.get(key) ?? [];
    list.push({ ...release, numericType: type });
    releasesByPageID.set(key, list);
  }

  const catalog = [];
  for (const [pageID, itemReleases] of releasesByPageID) {
    const vehicle = vehicleByPageID.get(pageID);
    if (!vehicle) continue;

    const origin = plainText(vehicle.Origin) || "Other / Original";
    if (EXCLUDED_ORIGINS.has(origin)) continue;

    itemReleases.sort((a, b) => {
      const yearDiff = Number(a.Year || 9999) - Number(b.Year || 9999);
      if (yearDiff !== 0) return yearDiff;
      return Number(a.ReleaseID || 9999) - Number(b.ReleaseID || 9999);
    });

    const first = itemReleases[0];
    const firstYear = Number(first.Year) || 0;
    const types = new Set(itemReleases.map((release) => release.numericType));
    const type = lineForTypes(types);
    const codes = itemReleases.map((release) => cleanProductCode(release.ToyNumber)).filter(Boolean);
    const productCode = codes[0] ?? "";
    const name = plainText(vehicle.Name) || plainText(first.ModelName) || `Vehicle ${pageID}`;
    const character = plainText(vehicle.Character) || name;
    const page = decodeEntities(vehicle.Page);
    const source = sourcePageURL(page);
    const releaseCount = itemReleases.length;
    const series = firstSeriesName(first.Series, firstYear);
    const isExclusive = types.has(6) || types.has(10);

    catalog.push({
      checked: false,
      built: false,
      name,
      number: `PCW-${pageID}`,
      productCode,
      action: "update",
      originalNumber: `PCW-${pageID}`,
      category: origin,
      character,
      difficulty: firstYear || null,
      firstReleaseYear: firstYear || null,
      sheets: releaseCount,
      releaseCount,
      releaseDate: firstYear ? String(firstYear) : "",
      link: source,
      instructionsLink: "",
      type,
      status: isExclusive ? "Exclusive" : "",
      series,
      "360View": "",
      description: `${name} is a ${type.toLowerCase()} release${character !== name ? ` of ${character}` : ""} from ${origin}. ${firstYear ? `First released in ${firstYear}` : "Release year not documented"}${productCode ? ` as ${productCode}` : ""}; ${releaseCount} documented release${releaseCount === 1 ? "" : "s"}.`,
      productimage: imageURL(plainText(vehicle.Photo)),
      source: SOURCE_URL,
      sourceLicense: "CC BY-SA 4.0",
    });
  }

  catalog.sort((a, b) => a.name.localeCompare(b.name) || a.number.localeCompare(b.number));
  return catalog;
}

const catalog = await buildCatalog();
if (catalog.length < 1400) throw new Error(`Catalogue unexpectedly small: ${catalog.length}`);
if (new Set(catalog.map((item) => item.number)).size !== catalog.length) throw new Error("Duplicate catalogue identifiers");

const serialized = `${JSON.stringify(catalog, null, 2)}\n`;
for (const output of [appOutput, workerOutput]) {
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, serialized, "utf8");
}

console.log(`Wrote ${catalog.length} released Cars die-cast variants.`);
