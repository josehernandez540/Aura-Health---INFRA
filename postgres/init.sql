DROP TABLE IF EXISTS
  appointment_history,
  appointments,
  medication_changes,
  treatment_approvals,
  treatments,
  risk_classifications,
  medical_records,
  notifications,
  reports,
  audit_logs,
  doctors,
  patients,
  users,
  roles
CASCADE;

DROP TYPE IF EXISTS
  user_role_enum,
  appointment_status_enum,
  treatment_status_enum,
  risk_level_enum,
  notification_type_enum,
  notification_status_enum,
  medical_record_source_enum,
  report_type_enum
CASCADE;

-- ================================================================
-- 1. EXTENSIONES
-- ================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ================================================================
-- 2. ENUMS
-- ================================================================
CREATE TYPE user_role_enum AS ENUM ('ADMIN', 'DOCTOR');

CREATE TYPE appointment_status_enum AS ENUM (
  'SCHEDULED',
  'CANCELLED',
  'COMPLETED',
  'NO_SHOW'
);

CREATE TYPE treatment_status_enum AS ENUM (
  'ACTIVE',
  'COMPLETED',
  'PENDING_APPROVAL'
);

CREATE TYPE risk_level_enum AS ENUM ('LOW', 'MEDIUM', 'HIGH');

CREATE TYPE notification_type_enum AS ENUM (
  'APPOINTMENT_REMINDER',
  'DAILY_AGENDA'
);

CREATE TYPE notification_status_enum AS ENUM ('PENDING', 'SENT', 'FAILED');

CREATE TYPE medical_record_source_enum AS ENUM ('INTERNAL', 'EXTERNAL');

CREATE TYPE report_type_enum AS ENUM ('CLINICAL');

-- ================================================================
-- 3. ROLES
-- ================================================================
CREATE TABLE roles (
  id   UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  name user_role_enum UNIQUE NOT NULL
);

-- ================================================================
-- 4. USERS
-- FIX: must_change_password es Boolean? en Prisma → nullable, sin NOT NULL
-- ================================================================
CREATE TABLE users (
  id                   UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
  email                TEXT      UNIQUE NOT NULL,
  password             TEXT      NOT NULL,
  role_id              UUID      NOT NULL,
  is_active            BOOLEAN   DEFAULT TRUE,
  must_change_password BOOLEAN   DEFAULT FALSE,        -- ← nullable, igual que Prisma
  created_at           TIMESTAMP DEFAULT NOW(),
  updated_at           TIMESTAMP DEFAULT NOW(),
  CONSTRAINT fk_user_role FOREIGN KEY (role_id) REFERENCES roles(id)
);

-- ================================================================
-- 5. AUDIT LOGS
-- FIX: columna era "entity" → debe ser "entity_type"
-- FIX: faltaba columna "severity"
-- ================================================================
CREATE TABLE audit_logs (
  id          UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID,
  action      TEXT      NOT NULL,
  entity_type TEXT,                                    -- ← nombre corregido
  entity_id   UUID,
  metadata    JSONB,
  severity    TEXT,                                    -- ← columna agregada
  created_at  TIMESTAMP DEFAULT NOW(),
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id)
);

-- ================================================================
-- 6. DOCTORS
-- FIX: faltaban status_changed_by y status_changed_at (REQ-02)
-- ================================================================
CREATE TABLE doctors (
  id                UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID      UNIQUE NOT NULL,
  name              TEXT      NOT NULL,
  specialization    TEXT,
  license_number    TEXT      UNIQUE,
  is_active         BOOLEAN   DEFAULT TRUE,
  status_changed_by UUID,                              -- ← agregado
  status_changed_at TIMESTAMP,                         -- ← agregado
  CONSTRAINT fk_doctor_user           FOREIGN KEY (user_id)           REFERENCES users(id),
  CONSTRAINT fk_doctor_status_changer FOREIGN KEY (status_changed_by) REFERENCES users(id)
);

-- ================================================================
-- 7. PATIENTS
-- FIX: faltaban is_active y updated_at (REQ-03)
-- ================================================================
CREATE TABLE patients (
  id              UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
  name            TEXT      NOT NULL,
  document_number TEXT      UNIQUE NOT NULL,
  birth_date      DATE,
  phone           TEXT,
  email           TEXT,
  is_active       BOOLEAN   DEFAULT TRUE,              -- ← agregado
  updated_at      TIMESTAMP DEFAULT NOW(),             -- ← agregado
  created_at      TIMESTAMP DEFAULT NOW()
);

-- ================================================================
-- 8. APPOINTMENTS (REQ-04)
-- ================================================================
CREATE TABLE appointments (
  id         UUID                    PRIMARY KEY DEFAULT uuid_generate_v4(),
  doctor_id  UUID                    NOT NULL,
  patient_id UUID                    NOT NULL,
  date       DATE                    NOT NULL,
  start_time TIME                    NOT NULL,
  end_time   TIME                    NOT NULL,
  status     appointment_status_enum DEFAULT 'SCHEDULED',
  created_by UUID,
  notes      TEXT,
  created_at TIMESTAMP               DEFAULT NOW(),
  CONSTRAINT fk_appointment_doctor  FOREIGN KEY (doctor_id)  REFERENCES doctors(id),
  CONSTRAINT fk_appointment_patient FOREIGN KEY (patient_id) REFERENCES patients(id),
  CONSTRAINT fk_created_by          FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Índice único: previene doble asignación de médico en mismo slot (crítico REQ-04)
CREATE UNIQUE INDEX unique_doctor_schedule
  ON appointments (doctor_id, date, start_time);

CREATE INDEX idx_appointment_doctor_date
  ON appointments (doctor_id, date);

-- ================================================================
-- 9. APPOINTMENT HISTORY
-- ================================================================
CREATE TABLE appointment_history (
  id             UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
  appointment_id UUID      NOT NULL,
  action         TEXT      NOT NULL,
  performed_by   UUID,
  created_at     TIMESTAMP DEFAULT NOW(),
  CONSTRAINT fk_history_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(id),
  CONSTRAINT fk_history_user        FOREIGN KEY (performed_by)   REFERENCES users(id)
);

-- ================================================================
-- 10. MEDICAL RECORDS
-- ================================================================
CREATE TABLE medical_records (
  id          UUID                       PRIMARY KEY DEFAULT uuid_generate_v4(),
  patient_id  UUID                       NOT NULL,
  uploaded_by UUID,
  file_url    TEXT                       NOT NULL,
  file_hash   TEXT,
  source      medical_record_source_enum,
  created_at  TIMESTAMP                  DEFAULT NOW(),
  CONSTRAINT fk_record_patient FOREIGN KEY (patient_id)  REFERENCES patients(id),
  CONSTRAINT fk_record_user    FOREIGN KEY (uploaded_by) REFERENCES users(id)
);

CREATE INDEX idx_medical_record_patient ON medical_records (patient_id);

-- ================================================================
-- 11. RISK CLASSIFICATIONS
-- ================================================================
CREATE TABLE risk_classifications (
  id                UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
  medical_record_id UUID            UNIQUE NOT NULL,
  risk_level        risk_level_enum,
  score             NUMERIC,
  created_at        TIMESTAMP       DEFAULT NOW(),
  CONSTRAINT fk_risk_record FOREIGN KEY (medical_record_id) REFERENCES medical_records(id)
);

-- ================================================================
-- 12. TREATMENTS
-- ================================================================
CREATE TABLE treatments (
  id          UUID                  PRIMARY KEY DEFAULT uuid_generate_v4(),
  patient_id  UUID                  NOT NULL,
  doctor_id   UUID                  NOT NULL,
  description TEXT                  NOT NULL,
  status      treatment_status_enum DEFAULT 'ACTIVE',
  created_at  TIMESTAMP             DEFAULT NOW(),
  CONSTRAINT fk_treatment_patient FOREIGN KEY (patient_id) REFERENCES patients(id),
  CONSTRAINT fk_treatment_doctor  FOREIGN KEY (doctor_id)  REFERENCES doctors(id)
);

CREATE INDEX idx_treatment_patient ON treatments (patient_id);

-- ================================================================
-- 13. TREATMENT APPROVALS
-- FIX: el schema Prisma NO define @unique en treatment_id → sin UNIQUE
-- ================================================================
CREATE TABLE treatment_approvals (
  id           UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
  treatment_id UUID      NOT NULL,                     -- ← sin UNIQUE
  approved_by  UUID,
  notes        TEXT,
  approved_at  TIMESTAMP DEFAULT NOW(),
  CONSTRAINT fk_approval_treatment FOREIGN KEY (treatment_id) REFERENCES treatments(id),
  CONSTRAINT fk_approval_user      FOREIGN KEY (approved_by)  REFERENCES users(id)
);

-- ================================================================
-- 14. MEDICATION CHANGES
-- ================================================================
CREATE TABLE medication_changes (
  id                  UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
  treatment_id        UUID      NOT NULL,
  previous_medication TEXT,
  new_medication      TEXT,
  changed_by          UUID,
  created_at          TIMESTAMP DEFAULT NOW(),
  CONSTRAINT fk_medication_treatment FOREIGN KEY (treatment_id) REFERENCES treatments(id),
  CONSTRAINT fk_medication_user      FOREIGN KEY (changed_by)   REFERENCES users(id)
);

-- ================================================================
-- 15. NOTIFICATIONS
-- FIX: faltaban entity_type y entity_id
-- ================================================================
CREATE TABLE notifications (
  id          UUID                     PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID                     NOT NULL,
  type        notification_type_enum,
  message     TEXT,
  status      notification_status_enum DEFAULT 'PENDING',
  entity_type TEXT,                                    -- ← agregado
  entity_id   UUID,                                    -- ← agregado
  sent_at     TIMESTAMP,
  CONSTRAINT fk_notification_user FOREIGN KEY (user_id) REFERENCES users(id)
);

-- ================================================================
-- 16. REPORTS
-- FIX: faltaban entity_type y entity_id
-- ================================================================
CREATE TABLE reports (
  id           UUID             PRIMARY KEY DEFAULT uuid_generate_v4(),
  generated_by UUID,
  type         report_type_enum,
  file_url     TEXT,
  entity_type  TEXT,                                   -- ← agregado
  entity_id    UUID,                                   -- ← agregado
  created_at   TIMESTAMP        DEFAULT NOW(),
  CONSTRAINT fk_report_user FOREIGN KEY (generated_by) REFERENCES users(id)
);

-- ================================================================
-- 17. DATA INICIAL — Roles
-- ================================================================
INSERT INTO roles (name) VALUES ('ADMIN'), ('DOCTOR');

-- ================================================================
-- 18. DATOS DE EJEMPLO
-- ================================================================
-- Contraseña para todos los usuarios de ejemplo: Admin123!
-- Hash bcrypt generado con saltRounds=10
-- ================================================================

-- ── Usuarios ──────────────────────────────────────────────────────────────────

INSERT INTO users (id, email, password, role_id, is_active, must_change_password)
VALUES
  (
    'a0000000-0000-4000-8000-000000000001',
    'admin@aura.com',
    '$2b$10$MkQli6rwFnzifalFY14ZweRk4Qs68nZz0GgTjonAhTjDUihgN63fe', -- Admin123!
    (SELECT id FROM roles WHERE name = 'ADMIN'),
    TRUE,
    FALSE
  ),
  (
    'a0000000-0000-4000-8000-000000000002',
    'dr.garcia@aura.com',
    '$2b$10$MkQli6rwFnzifalFY14ZweRk4Qs68nZz0GgTjonAhTjDUihgN63fe', -- Admin123!
    (SELECT id FROM roles WHERE name = 'DOCTOR'),
    TRUE,
    FALSE
  ),
  (
    'a0000000-0000-4000-8000-000000000003',
    'dr.martinez@aura.com',
    '$2b$10$MkQli6rwFnzifalFY14ZweRk4Qs68nZz0GgTjonAhTjDUihgN63fe', -- Admin123!
    (SELECT id FROM roles WHERE name = 'DOCTOR'),
    TRUE,
    TRUE   -- debe cambiar contraseña en primer login
  ),
  (
    'a0000000-0000-4000-8000-000000000004',
    'dr.lopez@aura.com',
    '$2b$10$MkQli6rwFnzifalFY14ZweRk4Qs68nZz0GgTjonAhTjDUihgN63fe', -- Admin123!
    (SELECT id FROM roles WHERE name = 'DOCTOR'),
    FALSE,  -- médico inactivo (para probar REQ-02)
    FALSE
  );

-- ── Médicos ───────────────────────────────────────────────────────────────────

INSERT INTO doctors (id, user_id, name, specialization, license_number, is_active)
VALUES
  (
    'b0000000-0000-4000-8000-000000000001',
    'a0000000-0000-4000-8000-000000000002',
    'Dr. Carlos García',
    'Cardiología',
    'MED-2024-001',
    TRUE
  ),
  (
    'b0000000-0000-4000-8000-000000000002',
    'a0000000-0000-4000-8000-000000000003',
    'Dra. Ana Martínez',
    'Pediatría',
    'MED-2024-002',
    TRUE
  ),
  (
    'b0000000-0000-4000-8000-000000000003',
    'a0000000-0000-4000-8000-000000000004',
    'Dr. Luis López',
    'Neurología',
    'MED-2024-003',
    FALSE  -- inactivo (para probar REQ-02)
  );

-- ── Pacientes ─────────────────────────────────────────────────────────────────

INSERT INTO patients (id, name, document_number, birth_date, phone, email, is_active)
VALUES
  (
    'c0000000-0000-4000-8000-000000000001',
    'María González',
    '1020304050',
    '1985-03-22',
    '+57 311 1234567',
    'maria.gonzalez@email.com',
    TRUE
  ),
  (
    'c0000000-0000-4000-8000-000000000002',
    'Juan Pérez',
    '9876543210',
    '1990-07-14',
    '+57 320 9876543',
    'juan.perez@email.com',
    TRUE
  ),
  (
    'c0000000-0000-4000-8000-000000000003',
    'Laura Rodríguez',
    '1122334455',
    '1978-11-30',
    '+57 315 5554433',
    'laura.rodriguez@email.com',
    TRUE
  ),
  (
    'c0000000-0000-4000-8000-000000000004',
    'Pedro Sánchez',
    '6677889900',
    '2001-05-08',
    '+57 318 7778899',
    NULL,
    FALSE  -- inactivo (para probar REQ-03)
  );

-- ── Citas ─────────────────────────────────────────────────────────────────────
-- Usa fechas futuras fijas para evitar errores de validación en pruebas manuales.
-- En los tests E2E se usan fechas de 2099 para garantizar que siempre sean futuras.

INSERT INTO appointments (
  id, doctor_id, patient_id, date, start_time, end_time, status, created_by, notes
)
VALUES
  (
    'd0000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000001',  -- Dr. García
    'c0000000-0000-4000-8000-000000000001',  -- María González
    '2099-06-10',
    '09:00',
    '09:30',
    'SCHEDULED',
    'a0000000-0000-4000-8000-000000000001',  -- creada por admin
    'Control cardiológico anual'
  ),
  (
    'd0000000-0000-4000-8000-000000000002',
    'b0000000-0000-4000-8000-000000000001',  -- Dr. García
    'c0000000-0000-4000-8000-000000000002',  -- Juan Pérez
    '2099-06-10',
    '10:00',
    '10:30',
    'SCHEDULED',
    'a0000000-0000-4000-8000-000000000001',
    'Primera consulta'
  ),
  (
    'd0000000-0000-4000-8000-000000000003',
    'b0000000-0000-4000-8000-000000000002',  -- Dra. Martínez
    'c0000000-0000-4000-8000-000000000003',  -- Laura Rodríguez
    '2099-06-11',
    '08:00',
    '08:45',
    'SCHEDULED',
    'a0000000-0000-4000-8000-000000000001',
    'Consulta pediátrica'
  ),
  (
    'd0000000-0000-4000-8000-000000000004',
    'b0000000-0000-4000-8000-000000000001',  -- Dr. García
    'c0000000-0000-4000-8000-000000000003',  -- Laura Rodríguez
    '2099-05-01',
    '14:00',
    '14:30',
    'COMPLETED',
    'a0000000-0000-4000-8000-000000000001',
    'Cita completada — revisión de resultados'
  ),
  (
    'd0000000-0000-4000-8000-000000000005',
    'b0000000-0000-4000-8000-000000000002',  -- Dra. Martínez
    'c0000000-0000-4000-8000-000000000001',  -- María González
    '2099-04-20',
    '11:00',
    '11:30',
    'CANCELLED',
    'a0000000-0000-4000-8000-000000000001',
    'Paciente canceló por viaje'
  );

-- ── Historial de citas ────────────────────────────────────────────────────────

INSERT INTO appointment_history (appointment_id, action, performed_by)
VALUES
  (
    'd0000000-0000-4000-8000-000000000004',
    'COMPLETED',
    'a0000000-0000-4000-8000-000000000001'
  ),
  (
    'd0000000-0000-4000-8000-000000000005',
    'CANCELLED',
    'a0000000-0000-4000-8000-000000000001'
  );

-- ── Tratamientos ──────────────────────────────────────────────────────────────

INSERT INTO treatments (id, patient_id, doctor_id, description, status)
VALUES
  (
    'e0000000-0000-4000-8000-000000000001',
    'c0000000-0000-4000-8000-000000000001',  -- María González
    'b0000000-0000-4000-8000-000000000001',  -- Dr. García
    'Tratamiento antihipertensivo con Losartán 50mg — una vez al día',
    'ACTIVE'
  ),
  (
    'e0000000-0000-4000-8000-000000000002',
    'c0000000-0000-4000-8000-000000000002',  -- Juan Pérez
    'b0000000-0000-4000-8000-000000000001',  -- Dr. García
    'Control de colesterol con Atorvastatina 20mg',
    'PENDING_APPROVAL'
  ),
  (
    'e0000000-0000-4000-8000-000000000003',
    'c0000000-0000-4000-8000-000000000003',  -- Laura Rodríguez
    'b0000000-0000-4000-8000-000000000002',  -- Dra. Martínez
    'Suplementación vitamínica — vitamina D y calcio',
    'COMPLETED'
  );

-- ── Aprobaciones de tratamientos ─────────────────────────────────────────────

INSERT INTO treatment_approvals (treatment_id, approved_by, notes)
VALUES
  (
    'e0000000-0000-4000-8000-000000000003',
    'a0000000-0000-4000-8000-000000000001',
    'Aprobado. Tratamiento completado satisfactoriamente.'
  );

-- ── Cambios de medicación ─────────────────────────────────────────────────────

INSERT INTO medication_changes (treatment_id, previous_medication, new_medication, changed_by)
VALUES
  (
    'e0000000-0000-4000-8000-000000000001',
    'Enalapril 10mg',
    'Losartán 50mg',
    'a0000000-0000-4000-8000-000000000002'
  );

-- ── Logs de auditoría de ejemplo ─────────────────────────────────────────────

INSERT INTO audit_logs (user_id, action, entity_type, entity_id, severity, metadata)
VALUES
  (
    'a0000000-0000-4000-8000-000000000001',
    'USER_LOGIN',
    'USER',
    'a0000000-0000-4000-8000-000000000001',
    'INFO',
    '{"email": "admin@aura.com"}'
  ),
  (
    'a0000000-0000-4000-8000-000000000001',
    'USER_CREATED',
    'DOCTOR',
    'b0000000-0000-4000-8000-000000000001',
    'INFO',
    '{"email": "dr.garcia@aura.com", "name": "Dr. Carlos García"}'
  ),
  (
    'a0000000-0000-4000-8000-000000000001',
    'APPOINTMENT_CREATED',
    'APPOINTMENT',
    'd0000000-0000-4000-8000-000000000001',
    'INFO',
    '{"doctorId": "b0000000-0000-4000-8000-000000000001", "date": "2099-06-10"}'
  ),
  (
    'a0000000-0000-4000-8000-000000000001',
    'DOCTOR_STATUS_CHANGED',
    'DOCTOR',
    'b0000000-0000-4000-8000-000000000003',
    'INFO',
    '{"newStatus": "INACTIVE"}'
  );

-- ── Notificaciones de ejemplo ─────────────────────────────────────────────────

INSERT INTO notifications (user_id, type, message, status, entity_type, entity_id)
VALUES
  (
    'a0000000-0000-4000-8000-000000000002',
    'APPOINTMENT_REMINDER',
    'Tiene una cita programada para mañana a las 09:00',
    'PENDING',
    'APPOINTMENT',
    'd0000000-0000-4000-8000-000000000001'
  ),
  (
    'a0000000-0000-4000-8000-000000000003',
    'DAILY_AGENDA',
    'Su agenda para hoy: 1 cita programada',
    'SENT',
    NULL,
    NULL
  );

-- ================================================================
-- FIN DEL SCRIPT
-- ================================================================
-- Usuarios de ejemplo:
--   admin@aura.com       → ADMIN    → contraseña: Admin123!
--   dr.garcia@aura.com   → DOCTOR   → contraseña: Admin123!
--   dr.martinez@aura.com → DOCTOR   → contraseña: Admin123! (debe cambiarla)
--   dr.lopez@aura.com    → DOCTOR   → contraseña: Admin123! (inactivo)
-- ================================================================