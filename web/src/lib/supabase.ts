import { createClient } from "@supabase/supabase-js";

// Auth only — never .from() or .rpc(). The API is the only holder of a
// database credential; the browser never queries Postgres directly.
export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY,
  { auth: { persistSession: true } },
);
