-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 4: Campus Clinic Medicine Dispensing
-- Student number: 201901101

DROP TABLE IF EXISTS dispensing_records;
DROP TABLE IF EXISTS medicines;
DROP PROCEDURE IF EXISTS dispense_medicine(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS reverse_dispensing(INT);

-- 1. Tables and sample data
CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    status         VARCHAR(20) NOT NULL DEFAULT 'DISPENSED'
                   CHECK (status IN ('DISPENSED', 'REVERSED'))
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol 500mg', 100),
    ('Amoxicillin 250mg', 15),
    ('Chloroquine 150mg', 0);

SELECT * FROM medicines ORDER BY medicine_id;

-- 2. IF / ELSIF / ELSE (0 = out of stock, 1-20 = low, >20 = sufficiently stocked)
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '% : OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity <= 20 THEN
            RAISE NOTICE '% : LOW stock (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '% : sufficiently stocked (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE (stock review days) and numeric FOR (shelf inspections)
DO $$
DECLARE
    d INT := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Stock review day %', d;
        d := d + 1;
    END LOOP;

    FOR insp IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', insp;
    END LOOP;
END $$;

-- 4. dispense_medicine procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_medicine_id INT, p_student_number VARCHAR, p_quantity INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: % (must be greater than zero)', p_quantity
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_stock < p_quantity THEN
        RAISE NOTICE 'Dispensing REJECTED for student %: requested %, only % in stock (medicine %)',
            p_student_number, p_quantity, v_stock, p_medicine_id;
        RETURN;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_quantity
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (medicine_id, student_number, quantity)
    VALUES (p_medicine_id, p_student_number, p_quantity);

    RAISE NOTICE 'Dispensing RECORDED for student %: % unit(s) of medicine %',
        p_student_number, p_quantity, p_medicine_id;
END $$;

-- 5. Two valid quantities and one exceeding stock
CALL dispense_medicine(1, '2024001', 10);   -- valid
CALL dispense_medicine(2, '2024002', 5);    -- valid
CALL dispense_medicine(2, '2024003', 50);   -- exceeds stock (10 left)

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 6. reverse_dispensing procedure (restores stock only once)
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INT;
    v_qty         INT;
    v_status      VARCHAR(20);
BEGIN
    SELECT medicine_id, quantity, status
      INTO v_medicine_id, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Dispensing record % does not exist', p_record_id;
        RETURN;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % is already reversed: stock not restored again', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_qty
    WHERE medicine_id = v_medicine_id;

    RAISE NOTICE 'Record % reversed: % unit(s) restored', p_record_id, v_qty;
END $$;

CALL reverse_dispensing(1);   -- restores stock
CALL reverse_dispensing(1);   -- second call: must NOT restore again

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 7. Explicit cursor: medicines below the low-stock threshold (20)
DO $$
DECLARE
    v_threshold CONSTANT INT := 20;
    cur_low CURSOR (p_limit INT) FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines WHERE stock_quantity < p_limit ORDER BY medicine_id;
    rec RECORD;
BEGIN
    OPEN cur_low(v_threshold);
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold (%): % has % unit(s)',
            v_threshold, rec.medicine_name, rec.stock_quantity;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. Negative dispensing quantity: handled with an EXCEPTION block
DO $$
BEGIN
    CALL dispense_medicine(1, '2024004', -5);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;