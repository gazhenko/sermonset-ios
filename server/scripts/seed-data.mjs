import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { hash } from "./client.mjs";
export async function seedData() {
  const root = fileURLToPath(
    new URL(
      "../../Packages/SermonSetCore/Sources/SermonSetCore/Resources/Samples/",
      import.meta.url,
    ),
  );
  const source = JSON.parse(await readFile(root + "samples.json", "utf8"));
  const churches = [
    {
      id: "sample-church-west",
      name: "Fictional Sample Fellowship West",
      city: "Portland",
      region: "OR",
      country: "US",
    },
    {
      id: "sample-church-south",
      name: "Fictional Sample Fellowship South",
      city: "Atlanta",
      region: "GA",
      country: "US",
    },
    {
      id: "sample-church-north",
      name: "Fictional Sample Fellowship North",
      city: "Minneapolis",
      region: "MN",
      country: "US",
    },
  ];
  const statements = churches.map((c) => ({
    query:
      "INSERT OR IGNORE INTO churches(id,name,city,region,country,website,verified,credit_policy,fictional) VALUES(?,?,?,?,?,NULL,1,'anonymous',1)",
    args: [c.id, c.name, c.city, c.region, c.country],
  }));
  const audio = [];
  const normalize = (s) =>
    s
      .normalize("NFKC")
      .toLowerCase()
      .replace(/[^\p{L}\p{N}]/gu, "");
  for (const [i, s] of source.sermons.entries()) {
    const church = churches[i % 3],
      id = "sample-" + s.slug,
      pub = "sample-publication-" + s.slug,
      asset = "sample-audio-" + s.slug,
      key = `private/audio/${asset}`;
    const bytes = await readFile(root + s.audioFile);
    if (hash(bytes) !== s.checksumSHA256)
      throw Error("Sample audio checksum mismatch: " + s.slug);
    const time = new Date(s.serviceDate).toISOString();
    statements.push({
      query:
        "INSERT OR IGNORE INTO sermons(id,church_id,title,title_normalized,preacher,service_date,primary_passage,passage_normalized,themes,sermon_type,city,region,country,summary,reflection_prompt,state,canonical_audio_id,church_verified,fictional,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'published',?,1,1,?)",
      args: [
        id,
        church.id,
        s.title,
        normalize(s.title),
        s.preacher,
        time,
        s.primaryPassage,
        normalize(s.primaryPassage),
        JSON.stringify(s.themes),
        s.sermonType,
        s.venue.city,
        s.venue.region,
        s.venue.country,
        s.summary,
        s.reflectionPrompt,
        asset,
        time,
      ],
    });
    statements.push(
      {
        query:
          "INSERT OR IGNORE INTO publications(id,sermon_id,state,rights_basis,audio_asset_id,created_at) VALUES(?,?,'published','fictionalSeed',?,?)",
        args: [pub, id, asset, time],
      },
      {
        query:
          "INSERT OR IGNORE INTO audio_assets(id,publication_id,sermon_id,storage_key,checksum,source_checksum,byte_count,duration,trim_start,trim_end,kind,state,uploaded,validated,upload_expires) VALUES(?,?,?,?,?,?,?,?,0,?,'enhancedCommunity','published',1,1,0)",
        args: [
          asset,
          pub,
          id,
          key,
          s.checksumSHA256,
          s.checksumSHA256,
          s.byteCount,
          s.duration,
          s.duration,
        ],
      },
      {
        query:
          "INSERT OR IGNORE INTO grants(asset_id,church_id,active,basis) VALUES(?,?,1,'fictionalSeed')",
        args: [asset, church.id],
      },
    );
    audio.push({ key, bytes });
  }
  return { statements, audio };
}
export function literal(value) {
  if (value === null) return "NULL";
  if (typeof value === "number") return String(value);
  return "'" + String(value).replace(/'/g, "''") + "'";
}
export function statementSQL(stmt) {
  let index = 0;
  return stmt.query.replace(/\?/g, () => literal(stmt.args[index++]));
}
