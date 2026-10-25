-- Forward-only follow-up (never edit a merged migration).
-- Automation idea #2 catch-up: the "student" and "enrolled" updates sent to
-- Admissions (features/admissions-callback) were best effort, so an update sent
-- while Admissions was down was lost. This remembers the last stage Admissions
-- accepted for each student, so what is missing can be sent again.
--
-- admissions_status_queue   one row per student: last stage Admissions accepted,
--                           failed attempts, last error. System table: no
--                           policies, no audit trigger, service role only.
-- record_admissions_status  writes the outcome of one send.
-- admissions_status_due     students whose current stage is newer than what
--                           Admissions has, and that are due for another try
--                           (5 minutes longer after each failure, up to 1 hour,
--                           20 attempts at most).
-- A student's current stage is 'enrolled' once a COR exists, else 'student'.

CREATE TABLE IF NOT EXISTS admissions_status_queue (
    student_id       uuid PRIMARY KEY REFERENCES students (id) ON DELETE CASCADE,
    stage_sent       text NULL CHECK (stage_sent IN ('student','enrolled')),
    attempts         integer NOT NULL DEFAULT 0,
    last_attempt_at  timestamptz NULL,
    last_error       text NULL,
    updated_at       timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE admissions_status_queue IS 'Last stage Admissions accepted for each student, with failed attempts. Read by the catch-up that re-sends missed status updates.';
ALTER TABLE admissions_status_queue ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION record_admissions_status(
  p_student uuid, p_stage text, p_ok boolean, p_error text DEFAULT NULL, p_permanent boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_stage IS NULL OR p_stage NOT IN ('student','enrolled') THEN
    RAISE EXCEPTION 'Unknown stage';
  END IF;

  IF p_ok THEN
    INSERT INTO admissions_status_queue (student_id, stage_sent, attempts, last_attempt_at, last_error)
    VALUES (p_student, p_stage, 0, now(), NULL)
    ON CONFLICT (student_id) DO UPDATE SET
      stage_sent      = CASE WHEN admissions_status_queue.stage_sent = 'enrolled' THEN 'enrolled' ELSE EXCLUDED.stage_sent END,
      attempts        = 0,
      last_attempt_at = now(),
      last_error      = NULL,
      updated_at      = now();
  ELSE
    -- A permanent failure (Admissions refused the details) is not tried again.
    INSERT INTO admissions_status_queue (student_id, stage_sent, attempts, last_attempt_at, last_error)
    VALUES (p_student, NULL, CASE WHEN p_permanent THEN 20 ELSE 1 END, now(), left(p_error, 500))
    ON CONFLICT (student_id) DO UPDATE SET
      attempts        = least(admissions_status_queue.attempts + CASE WHEN p_permanent THEN 20 ELSE 1 END, 20),
      last_attempt_at = now(),
      last_error      = left(p_error, 500),
      updated_at      = now();
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION admissions_status_due(p_limit integer DEFAULT 5)
RETURNS TABLE (student_id uuid, applicant_ref varchar, student_number varchar, stage text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, a.applicant_ref, s.student_number,
         CASE WHEN c.id IS NULL THEN 'student' ELSE 'enrolled' END
    FROM students s
    JOIN applicants a ON a.id = s.applicant_id
    LEFT JOIN cors c ON c.student_id = s.id
    LEFT JOIN admissions_status_queue q ON q.student_id = s.id
   WHERE q.stage_sent IS DISTINCT FROM (CASE WHEN c.id IS NULL THEN 'student' ELSE 'enrolled' END)
     AND coalesce(q.attempts, 0) < 20
     AND (q.last_attempt_at IS NULL
          OR q.last_attempt_at <= now() - least(q.attempts, 12) * interval '5 minutes')
   ORDER BY coalesce(q.last_attempt_at, s.created_at), s.id
   LIMIT greatest(p_limit, 0)
$$;

REVOKE EXECUTE ON FUNCTION record_admissions_status(uuid, text, boolean, text, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admissions_status_due(integer) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION record_admissions_status(uuid, text, boolean, text, boolean) FROM anon;
    REVOKE EXECUTE ON FUNCTION admissions_status_due(integer) FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION record_admissions_status(uuid, text, boolean, text, boolean) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION admissions_status_due(integer) FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON admissions_status_queue TO service_role;
    GRANT EXECUTE ON FUNCTION record_admissions_status(uuid, text, boolean, text, boolean) TO service_role;
    GRANT EXECUTE ON FUNCTION admissions_status_due(integer) TO service_role;
  END IF;
END $$;
