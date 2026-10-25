// app/api/admissions/programs/route.ts
//
// The program list, for PLP Admissions to check its own course list against
// (automation idea #4). Authorization: Bearer <ADMISSIONS_INTAKE_SECRET>, the
// same secret as the intake call. Read only. Middleware skips this path.
// Answer: { "programs": [ { "code": "BSIT", "name": "BS Information Technology" } ] }
import { NextResponse, type NextRequest } from 'next/server';
import { createAdminClient } from '@/lib/supabase/admin';
import { hasValidSecret } from '@/features/admissions-intake/secret';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const secret = process.env.ADMISSIONS_INTAKE_SECRET;
  if (!secret) {
    return NextResponse.json({ error: 'The intake endpoint is not configured.' }, { status: 503 });
  }
  if (!hasValidSecret(request.headers.get('authorization'), secret)) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 401 });
  }

  try {
    const { data, error } = await createAdminClient().from('programs').select('code, name').order('code');
    if (error) return NextResponse.json({ error: 'Could not read the program list.' }, { status: 500 });
    return NextResponse.json({ programs: data ?? [] });
  } catch (error) {
    console.error('Program list failed', error);
    return NextResponse.json({ error: 'Could not read the program list.' }, { status: 500 });
  }
}
