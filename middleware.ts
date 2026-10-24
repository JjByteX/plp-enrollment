// middleware.ts
//
// Runs before every page request. It refreshes the Supabase session and
// sends signed-out visitors to /login when they open a role area.
// Which role may open which area is checked in each area's layout
// (lib/auth/session.ts, requireArea). The database enforces the real limits.
//
// Next 16 renames this file to proxy.ts. The code stays the same.
import { NextResponse, type NextRequest } from 'next/server';
import { updateSession } from '@/lib/supabase/middleware';
import { isArea } from '@/lib/auth/roles';

export async function middleware(request: NextRequest) {
  const { response, signedIn } = await updateSession(request);

  const firstSegment = request.nextUrl.pathname.split('/')[1];
  if (!signedIn && isArea(firstSegment)) {
    const redirect = NextResponse.redirect(new URL('/login', request.url));
    // Keep any cookies Supabase just wrote on the original response.
    response.cookies.getAll().forEach((cookie) => redirect.cookies.set(cookie));
    return redirect;
  }

  return response;
}

// Skips static files and the Admissions intake endpoint (step 5), which is
// called by another system with a shared secret, not by a signed-in person.
export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|api/admissions/intake|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
};
