// app/auth/confirm/route.ts
//
// Landing point for the emailed invite and password links. The email template
// links here with a token_hash. This checks it, signs the person in (the
// session cookie is written by lib/supabase/server.ts) and sends them to
// /set-password. A bad or used link ends up there too, where the page shows
// that the link has expired.
import { NextResponse, type NextRequest } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const tokenHash = searchParams.get('token_hash');
  const type = searchParams.get('type');

  if (tokenHash && (type === 'invite' || type === 'recovery')) {
    const supabase = createClient();
    await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
  }

  return NextResponse.redirect(new URL('/set-password', origin));
}
