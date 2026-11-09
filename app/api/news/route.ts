import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function GET() {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    return NextResponse.json(
      { status: "not_configured", message: "База новин ще не підключена.", data: [] },
      { status: 503, headers: { "Cache-Control": "no-store" } }
    );
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("news_articles")
    .select("id, title, summary, language, source_name, source_url, published_at, created_at")
    .eq("status", "published")
    .order("published_at", { ascending: false })
    .limit(30);

  if (error) {
    return NextResponse.json({ status: "error", message: "Не вдалося отримати новини.", data: [] }, { status: 500 });
  }

  return NextResponse.json(
    { status: "ok", data },
    { headers: { "Cache-Control": "no-store" } }
  );
}
