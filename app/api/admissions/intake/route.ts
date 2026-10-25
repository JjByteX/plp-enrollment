// app/api/admissions/intake/route.ts
//
// The one inbound call from PLP Admissions (decision-log.md #1 and #11).
// Authorization: Bearer <ADMISSIONS_INTAKE_SECRET>, JSON body described in
// features/admissions-intake/schema.ts. Middleware skips this path.
// Repeating a send is safe, so Admissions' retry button calls this same endpoint.
import { NextResponse, type NextRequest } from 'next/server';
import { processIntake } from '@/features/admissions-intake/process';
import { hasValidSecret } from '@/features/admissions-intake/secret';

export async function POST(request: NextRequest) {
  const secret = process.env.ADMISSIONS_INTAKE_SECRET;
  if (!secret) {
    return NextResponse.json({ error: 'The intake endpoint is not configured.' }, { status: 503 });
  }
  if (!hasValidSecret(request.headers.get('authorization'), secret)) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 401 });
  }

  let raw: unknown = null;
  try {
    raw = await request.json();
  } catch {
    // Not JSON: processIntake rejects it and logs it.
  }

  const outcome = await processIntake(raw);
  return NextResponse.json(outcome.body, { status: outcome.httpStatus });
}
