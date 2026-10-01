-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 2: Computer Laboratory Reservations
-- Student number: 201901101

DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;
DROP PROCEDURE IF EXISTS reserve_workstations(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS cancel_reservation(INT);

-- 1. Tables and sample data
CREATE TABLE lab_sessions (
    session_id             SERIAL PRIMARY KEY,
    session_name           VARCHAR(100) NOT NULL,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    session_id     INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer       VARCHAR(100) NOT NULL,
    workstations   INT NOT NULL CHECK (workstations > 0),
    status         VARCHAR(20) NOT NULL DEFAULT 'RESERVED'
                   CHECK (status IN ('RESERVED', 'CANCELLED'))
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 - Programming Lab', 30),
    ('Tuesday 10:00 - Networking Lab', 4),
    ('Wednesday 14:00 - Database Lab', 0);

SELECT * FROM lab_sessions ORDER BY session_id;

-- 2. IF / ELSIF / ELSE (0 = full, 1-5 = nearly full, >5 = enough)
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT session_name, available_workstations
               FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '% : FULL', rec.session_name;
        ELSIF rec.available_workstations <= 5 THEN
            RAISE NOTICE '% : NEARLY FULL (% left)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '% : enough workstations (% left)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE (preparation reminders) and numeric FOR (workstation checks)
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', n;
        n := n + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', chk;
    END LOOP;
END $$;

-- 4. reserve_workstations procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id INT, p_lecturer VARCHAR, p_workstations INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_workstations IS NULL OR p_workstations <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)',
            p_workstations USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_available < p_workstations THEN
        RAISE NOTICE 'Reservation REJECTED for %: requested %, only % available (session %)',
            p_lecturer, p_workstations, v_available, p_session_id;
        RETURN;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations - p_workstations
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations)
    VALUES (p_session_id, p_lecturer, p_workstations);

    RAISE NOTICE 'Reservation RECORDED for %: % workstation(s) in session %',
        p_lecturer, p_workstations, p_session_id;
END $$;

-- 5. Two valid reservations and one exceeding capacity
CALL reserve_workstations(1, 'Dr. Banda', 20);   -- valid
CALL reserve_workstations(2, 'Mr. Phiri', 3);    -- valid
CALL reserve_workstations(2, 'Ms. Mwansa', 10);  -- exceeds capacity (1 left)

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 6. cancel_reservation procedure (releases workstations only once)
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_count      INT;
    v_status     VARCHAR(20);
BEGIN
    SELECT session_id, workstations, status
      INTO v_session_id, v_count, v_status
    FROM reservations WHERE reservation_id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Reservation % does not exist', p_reservation_id;
        RETURN;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled: nothing released', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions
    SET available_workstations = available_workstations + v_count
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled: % workstation(s) released', p_reservation_id, v_count;
END $$;

CALL cancel_reservation(1);   -- releases workstations
CALL cancel_reservation(1);   -- second call: must NOT release again

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 7. Explicit cursor: sessions with few workstations remaining (5 or fewer)
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions WHERE available_workstations <= 5 ORDER BY session_id;
    rec RECORD;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations left: session % "%" has %',
            rec.session_id, rec.session_name, rec.available_workstations;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. Request zero workstations: handled with an EXCEPTION block
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Zulu', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;