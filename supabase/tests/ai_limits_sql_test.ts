// Runs the real migration in an in-process Postgres (PGlite) and checks the limit functions.
// deno test --allow-read --allow-env --allow-net supabase/tests/ai_limits_sql_test.ts
import { assertEquals } from "jsr:@std/assert@1.0.13";
import { PGlite } from "npm:@electric-sql/pglite@0.5.13";

async function db() {
  const pg = new PGlite();
  // What Supabase provides that the migration relies on.
  await pg.exec(`
    create role anon; create role authenticated;
    create schema auth; create table auth.users (id uuid primary key);
    insert into auth.users values ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
  `);
  await pg.exec(await Deno.readTextFile(new URL("../migrations/20261106000000_ai_limits.sql", import.meta.url)));
  return pg;
}

const take = async (pg: PGlite, buckets: string[], limits: number[], window = "2026-11-06T00:00:00Z") =>
  (await pg.query<{ r: number }>(`select ai_take($1::text[], $2::timestamptz[], $3::int[]) as r`,
    [buckets, buckets.map(() => window), limits])).rows[0].r;

Deno.test("a free user's 5th scan of the day is refused, and nothing is counted for it", async () => {
  const pg = await db();
  const b = ["global", "ip:x", "user:u1:scan", "minute:u1"];
  for (let i = 0; i < 4; i++) assertEquals(await take(pg, b, [5000, 80, 4, 999]), 0);
  assertEquals(await take(pg, b, [5000, 80, 4, 999]), 3);   // the user's daily bucket is full
  const g = (await pg.query<{ count: number }>(`select count from ai_usage where bucket = 'global'`)).rows[0];
  assertEquals(g.count, 4, "the refused call took nothing from the global budget");
});

Deno.test("the global cap stops everyone", async () => {
  const pg = await db();
  assertEquals(await take(pg, ["global", "user:a:scan"], [2, 30]), 0);
  assertEquals(await take(pg, ["global", "user:b:scan"], [2, 30]), 0);
  assertEquals(await take(pg, ["global", "user:c:scan"], [2, 30]), 1);
});

Deno.test("a new day resets the user's count", async () => {
  const pg = await db();
  for (let i = 0; i < 4; i++) await take(pg, ["user:u1:scan"], [4]);
  assertEquals(await take(pg, ["user:u1:scan"], [4]), 1);
  assertEquals(await take(pg, ["user:u1:scan"], [4], "2026-11-07T00:00:00Z"), 0);
});

Deno.test("many requests at once can't get past the limit", async () => {
  const pg = await db();
  const results = await Promise.all(Array.from({ length: 25 }, () => take(pg, ["user:u1:scan"], [4])));
  assertEquals(results.filter((r) => r === 0).length, 4);
});

Deno.test("a failed model call gives the units back", async () => {
  const pg = await db();
  const b = ["global", "user:u1:scan"];
  await take(pg, b, [10, 4]);
  await pg.query(`select ai_give_back($1::text[], $2::timestamptz[])`, [b, b.map(() => "2026-11-06T00:00:00Z")]);
  const used = (await pg.query<{ n: number }>(`select ai_used_today('user:u1:scan', '2026-11-06T00:00:00Z') as n`)).rows[0].n;
  assertEquals(used, 0);
});

Deno.test("one subscription unlocks one account only", async () => {
  const pg = await db();
  const claim = async (user: string) => (await pg.query<{ ok: boolean }>(
    `select ai_claim_entitlement($1::uuid, 'otid-1', 'com.omsilwal.NutriCorePrimal.pro.annual', now() + interval '1 year', 'Sandbox') as ok`,
    [user])).rows[0].ok;
  assertEquals(await claim("00000000-0000-0000-0000-000000000001"), true);
  assertEquals(await claim("00000000-0000-0000-0000-000000000001"), true, "the owner can keep using it");
  assertEquals(await claim("00000000-0000-0000-0000-000000000002"), false, "someone else presenting it gets nothing");
});

Deno.test("the app's roles can't call the limit functions or read the tables", async () => {
  const pg = await db();
  const grants = await pg.query<{ fn: string }>(`
    select p.proname as fn from pg_proc p
    where p.proname like 'ai_%' and has_function_privilege('authenticated', p.oid, 'execute')`);
  assertEquals(grants.rows, []);
  const rls = await pg.query<{ relname: string }>(`
    select relname from pg_class where relname in ('ai_usage', 'ai_entitlements', 'ai_log') and not relrowsecurity`);
  assertEquals(rls.rows, []);
});
