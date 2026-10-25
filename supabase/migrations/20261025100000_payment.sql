-- ============================================================
-- supabase/migrations/20261025100000_payment.sql
-- Step 10: payment.
--
-- Forward-only. The payments table, the pending row the slip opens when
-- payment is required, the Finance/Admin gate and the per-program toggle
-- (program_payment_settings, audited) are already in 20261025000000_init.sql.
-- This adds:
--   - record_payment: Finance or Admin records and clears one payment, with the
--     student's notification, in one transaction
--   - payment_queue: the pending or cleared list with name, program and section
--     (Finance cannot read applicants, so a plain query cannot join them)
--   - my_payment_status: the signed-in student's own payment state
--
-- The toggle needs no function: Finance and Admin update
-- program_payment_settings directly and the audit trigger records it. It only
-- affects slips issued afterwards; each slip keeps its own snapshot.
-- No partial payments: a payment clears only when the amount paid covers the
-- amount due.
-- ============================================================

-- ============================================================
-- 1. Record and clear one payment
-- ============================================================
CREATE OR REPLACE FUNCTION record_payment(
  p_student uuid, p_amount_due numeric, p_amount_paid numeric, p_receipt_no text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_payment payments%ROWTYPE;
  v_user    uuid;
  v_due     numeric;
  v_paid    numeric;
  v_receipt text := nullif(btrim(coalesce(p_receipt_no, '')), '');
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('finance','admin') THEN
    RAISE EXCEPTION 'Only Finance or Admin can record a payment';
  END IF;

  IF p_amount_due IS NULL OR p_amount_due < 0 OR p_amount_due > 9999999999.99 THEN
    RAISE EXCEPTION 'Enter the amount due';
  END IF;
  IF p_amount_paid IS NULL OR p_amount_paid < 0 OR p_amount_paid > 9999999999.99 THEN
    RAISE EXCEPTION 'Enter the amount paid';
  END IF;
  v_due  := round(p_amount_due, 2);
  v_paid := round(p_amount_paid, 2);
  IF v_paid < v_due THEN
    RAISE EXCEPTION 'The amount paid must cover the amount due';
  END IF;
  IF v_paid > 0 AND v_receipt IS NULL THEN
    RAISE EXCEPTION 'Enter the receipt number';
  END IF;
  IF v_receipt IS NOT NULL AND length(v_receipt) > 60 THEN
    RAISE EXCEPTION 'The receipt number is longer than 60 characters';
  END IF;

  -- Two Finance staff on the same student queue here; the second one then
  -- finds it cleared and stops.
  SELECT * INTO v_payment FROM payments WHERE student_id = p_student FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This student has no payment to record';
  END IF;
  IF v_payment.status = 'cleared' THEN
    RAISE EXCEPTION 'This payment was already recorded';
  END IF;

  -- The gate trigger stamps recorded_by and cleared_at on the way to cleared.
  UPDATE payments
     SET amount_due = v_due, amount_paid = v_paid, receipt_no = v_receipt, status = 'cleared'
   WHERE id = v_payment.id;

  SELECT a.user_id INTO v_user
    FROM students st JOIN applicants a ON a.id = st.applicant_id
   WHERE st.id = p_student;

  INSERT INTO notifications (user_id, kind, title, message)
  VALUES (
    v_user, 'payment_cleared', 'Your payment is cleared',
    'Finance recorded your payment. Next, the Registrar issues your COR.'
  );

  RETURN v_payment.id;
END;
$$;

-- ============================================================
-- 2. The Finance list
--    p_status is 'pending' (lowest student number first) or 'cleared'
--    (latest first). Finance and Admin only.
-- ============================================================
CREATE OR REPLACE FUNCTION payment_queue(p_status text)
RETURNS TABLE (
  student_id     uuid,
  student_number text,
  full_name      text,
  program_code   text,
  section        text,
  amount_due     numeric,
  amount_paid    numeric,
  receipt_no     text,
  cleared_at     timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF app_role() IS NULL OR app_role() NOT IN ('finance','admin') THEN
    RAISE EXCEPTION 'Only Finance or Admin can see payments';
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('pending','cleared') THEN
    RAISE EXCEPTION 'Unknown payment status';
  END IF;

  RETURN QUERY
  SELECT st.id,
         st.student_number::text,
         u.full_name::text,
         p.code::text,
         (p.code || ' Year ' || sec.year_level || ' - ' || sec.name)::text,
         pay.amount_due::numeric,
         pay.amount_paid::numeric,
         pay.receipt_no::text,
         pay.cleared_at
    FROM payments pay
    JOIN students st ON st.id = pay.student_id
    JOIN applicants a ON a.id = st.applicant_id
    JOIN users u ON u.id = a.user_id
    JOIN programs p ON p.id = a.program_id
    LEFT JOIN student_sections ss ON ss.student_id = st.id
    LEFT JOIN sections sec ON sec.id = ss.section_id
   WHERE pay.status = p_status
   ORDER BY (CASE WHEN pay.status = 'cleared' THEN pay.cleared_at END) DESC NULLS LAST,
            st.student_number;
END;
$$;

-- ============================================================
-- 3. The signed-in student's own payment state
--    'pending' or 'cleared'; null when payment is not required or for
--    anyone who is not a student. Same pattern as my_open_late_items.
-- ============================================================
CREATE OR REPLACE FUNCTION my_payment_status() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT pay.status FROM payments pay WHERE pay.student_id = my_student_id()
$$;

-- ============================================================
-- 4. Who may call them. The functions also check the role themselves.
-- ============================================================
REVOKE EXECUTE ON FUNCTION record_payment(uuid, numeric, numeric, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION payment_queue(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION my_payment_status() FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION record_payment(uuid, numeric, numeric, text) FROM anon;
    REVOKE EXECUTE ON FUNCTION payment_queue(text) FROM anon;
    REVOKE EXECUTE ON FUNCTION my_payment_status() FROM anon;
  END IF;
END $$;
