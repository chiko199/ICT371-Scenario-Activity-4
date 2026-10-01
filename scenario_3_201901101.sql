-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 3: Student Hostel Room Allocation
-- Student number: 201901101

DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;
DROP PROCEDURE IF EXISTS allocate_room(VARCHAR, INT);
DROP PROCEDURE IF EXISTS check_out(INT);

-- 1. Tables and sample data
CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_number      VARCHAR(10) NOT NULL UNIQUE,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED'
                   CHECK (status IN ('ALLOCATED', 'COMPLETE'))
);

INSERT INTO hostel_rooms (room_number, available_spaces) VALUES
    ('A101', 4),
    ('B202', 1),
    ('C303', 0);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- 2. IF / ELSIF / ELSE (0 = full, 1 = one space left, otherwise several)
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT room_number, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % : FULL', rec.room_number;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE 'Room % : ONE space left', rec.room_number;
        ELSE
            RAISE NOTICE 'Room % : several spaces (%)', rec.room_number, rec.available_spaces;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE (inspection days) and numeric FOR (room checks)
DO $$
DECLARE
    d INT := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', d;
        d := d + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', chk;
    END LOOP;
END $$;

-- 4. allocate_room procedure
CREATE OR REPLACE PROCEDURE allocate_room(p_student_number VARCHAR, p_room_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_spaces INT;
BEGIN
    IF p_student_number IS NULL OR TRIM(p_student_number) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT available_spaces INTO v_spaces
    FROM hostel_rooms WHERE room_id = p_room_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_spaces < 1 THEN
        RAISE NOTICE 'Allocation REJECTED for student %: room % is full',
            p_student_number, p_room_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id)
    VALUES (p_student_number, p_room_id);

    RAISE NOTICE 'Allocation RECORDED: student % to room %', p_student_number, p_room_id;
END $$;

-- 5. Two valid allocations and one to a full room
CALL allocate_room('2024001', 1);   -- valid
CALL allocate_room('2024002', 2);   -- valid (room B202 becomes full)
CALL allocate_room('2024003', 3);   -- room C303 is full

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 6. check_out procedure (frees a space only once)
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT room_id, status INTO v_room_id, v_status
    FROM allocations WHERE allocation_id = p_allocation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Allocation % does not exist', p_allocation_id;
        RETURN;
    END IF;

    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % already checked out: no space freed', p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations SET status = 'COMPLETE' WHERE allocation_id = p_allocation_id;
    UPDATE hostel_rooms SET available_spaces = available_spaces + 1
    WHERE room_id = v_room_id;

    RAISE NOTICE 'Allocation % checked out: one space freed in room %', p_allocation_id, v_room_id;
END $$;

CALL check_out(2);   -- frees one space in B202
CALL check_out(2);   -- second call: must NOT free another space

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 7. Explicit cursor: full or nearly full rooms (1 space or fewer)
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_number, available_spaces
        FROM hostel_rooms WHERE available_spaces <= 1 ORDER BY room_id;
    rec RECORD;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO rec;
        EXIT WHEN NOT FOUND;
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % is FULL', rec.room_number;
        ELSE
            RAISE NOTICE 'Room % is NEARLY FULL (% space left)', rec.room_number, rec.available_spaces;
        END IF;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- 8. Blank student number: handled with an EXCEPTION block
DO $$
BEGIN
    CALL allocate_room('   ', 1);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;