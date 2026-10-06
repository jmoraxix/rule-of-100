import { createBrowserClient } from "@supabase/ssr";
import { supabaseEnv } from "./env";

export const createClient = () => createBrowserClient(supabaseEnv.url, supabaseEnv.anonKey);
