# Gather

A Gather social app backed by local Supabase.

## Local development

Requirements: Docker Desktop, Node.js, and the Supabase CLI.

```sh
npm install
npm run supabase:start
npm run supabase:status
```

Copy `.env.example` to `.env.local`, then replace `your-local-anon-key` with the
`ANON_KEY` printed by `npm run supabase:status`. This workspace already has a
local `.env.local` configured.

```sh
npm run dev
```

The app runs at http://127.0.0.1:5173 and Supabase Studio runs at
http://127.0.0.1:57323.

Use `npm run supabase:reset` to recreate the database from
`supabase/schema.sql` and `supabase/storage.sql`. This deletes local app data.
