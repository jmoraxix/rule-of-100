// Static references so Next inlines NEXT_PUBLIC_* into the browser bundle.
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    "Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY. " +
      "Locally, copy them from `pnpm exec supabase status` into .env.local.",
  );
}

export const supabaseEnv = { url, anonKey };
