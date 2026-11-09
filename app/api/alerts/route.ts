import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    return NextResponse.json(
      { status: "not_configured", message: "Офіційні джерела та база даних ще не підключені.", data: [] },
      { status: 503, headers: { "Cache-Control": "no-store" } }
    );
  }

  const { searchParams } = new URL(request.url);
  const cityId = searchParams.get("city_id");
  const supabase = await createSupabaseServerClient();

  let query = supabase
    .from("alert_events")
    .select("id, source_id, region_name, city_name, event_type, severity, title, body, source_url, occurred_at, verified_at, expires_at")
    .eq("status", "published")
    .order("occurred_at", { ascending: false })
    .limit(50);

  if (cityId) query = query.eq("city_id", cityId);

  const { data, error } = await query;
  if (error) {
    return NextResponse.json({ status: "error", message: "Не вдалося отримати перевірені повідомлення.", data: [] }, { status: 500 });
  }

  return NextResponse.json(
    { status: "ok", data },
    { headers: { "Cache-Control": "no-store" } }
  );
}
