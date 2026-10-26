// lib/failure.ts
//
// Turns a Postgres error from a server action into the message the person
// sees. A deliberate refusal from the database (RAISE EXCEPTION, code P0001)
// already carries a plain sentence, so it is shown as is. A feature can map
// further codes (for example 23505, a duplicate) to its own sentence;
// everything else gets the fallback so no raw database text leaks out.
export type DbError = { code?: string; message: string };

export type ActionError = { error: string };

export type Failure = (error: DbError, fallback: string) => ActionError;

export function failureWith(byCode: Record<string, string> = {}): Failure {
  return (error, fallback) => {
    if (error.code === 'P0001') return { error: error.message };
    const known = error.code ? byCode[error.code] : undefined;
    return { error: known ?? fallback };
  };
}

// P0001 or the fallback, for features with no extra codes.
export const failure: Failure = failureWith();
