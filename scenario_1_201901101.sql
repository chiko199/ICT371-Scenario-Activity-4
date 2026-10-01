-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 1: University Library Book Loans
-- Student number: 201901101

DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;
DROP PROCEDURE IF EXISTS borrow_book(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS return_book(INT);

-- 1. Tables and sample data
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(20) NOT NULL DEFAULT 'BORROWED'
                   CHECK (loan_status IN ('BORROWED', 'RETURNED')),
    loan_date      DATE NOT NULL DEFAULT CURRENT_DATE
);

INSERT INTO books (title, available_copies) VALUES
    ('Database Systems', 10),
    ('Operating Systems', 3),
    ('Computer Networks', 0);

SELECT * FROM books ORDER BY book_id;

-- 2. IF / ELSIF / ELSE (0 = unavailable, 1-3 = low, >3 = sufficiently stocked)
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '% : UNAVAILABLE (% copies)', rec.title, rec.available_copies;
        ELSIF rec.available_copies <= 3 THEN
            RAISE NOTICE '% : LOW on copies (% copies)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '% : sufficiently stocked (% copies)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE (overdue reminders) and numeric FOR (shelf numbers)
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', n;
        n := n + 1;
    END LOOP;

    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', shelf;
    END LOOP;
END $$;

-- 4. borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id INT, p_student_number VARCHAR, p_quantity INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_quantity
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Loan REJECTED for student %: requested %, only % available (book %)',
            p_student_number, p_quantity, v_available, p_book_id;
        RETURN;
    END IF;

    UPDATE books SET available_copies = available_copies - p_quantity
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity)
    VALUES (p_book_id, p_student_number, p_quantity);

    RAISE NOTICE 'Loan RECORDED for student %: % copy(ies) of book %',
        p_student_number, p_quantity, p_book_id;
END $$;

-- 5. Two valid loans and one request exceeding available copies
CALL borrow_book(1, '201901101', 2);   -- valid
CALL borrow_book(2, '201901101', 1);   -- valid
CALL borrow_book(2, '201901101', 5);   -- exceeds available copies (only 2 left)

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 6. return_book procedure (restores copies only once)
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
    v_qty     INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT book_id, quantity, loan_status
      INTO v_book_id, v_qty, v_status
    FROM book_loans WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist', p_loan_id;
        RETURN;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned: no copies restored', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_qty
    WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned: % copy(ies) restored', p_loan_id, v_qty;
END $$;

CALL return_book(1);   -- first call: restores copies
CALL return_book(1);   -- second call: must NOT restore again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 7. Explicit cursor: books with few copies remaining (3 or fewer)
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books WHERE available_copies <= 3 ORDER BY book_id;
    rec RECORD;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies left: book % "%" has % copy(ies)',
            rec.book_id, rec.title, rec.available_copies;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. Borrow zero copies: handled with an EXCEPTION block
DO $$
BEGIN
    CALL borrow_book(1, '201901101', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;