-- =========================
-- EXTENSIONES
-- =========================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================
-- ENUMS
-- =========================
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

CREATE TYPE risk_level_enum AS ENUM (
  'LOW',
  'MEDIUM',
  'HIGH'
);

CREATE TYPE notification_type_enum AS ENUM (
  'APPOINTMENT_REMINDER',
  'DAILY_AGENDA'
);

CREATE TYPE notification_status_enum AS ENUM (
  'PENDING',
  'SENT',
  'FAILED'
);

CREATE TYPE medical_record_source_enum AS ENUM (
  'INTERNAL',
  'EXTERNAL'
);

CREATE TYPE report_type_enum AS ENUM (
  'CLINICAL'
);

-- =========================
-- ROLES Y USUARIOS
-- =========================

CREATE TABLE roles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name user_role_enum UNIQUE NOT NULL
);

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  role_id UUID NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (role_id) REFERENCES roles(id)
);

-- =========================
-- AUDITORÍA 
-- =========================

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID,
  action TEXT NOT NULL,
  entity_type TEXT,
  entity_id UUID,
  metadata JSONB,
  severity TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- =========================
-- DOCTORES Y PACIENTES
-- =========================

CREATE TABLE doctors (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID UNIQUE NOT NULL,
  name TEXT NOT NULL,
  specialization TEXT,
  license_number TEXT UNIQUE,
  is_active BOOLEAN DEFAULT TRUE,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE patients (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  document_number TEXT UNIQUE NOT NULL,
  birth_date DATE,
  phone TEXT,
  email TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- CITAS
-- =========================

CREATE TABLE appointments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  doctor_id UUID NOT NULL,
  patient_id UUID NOT NULL,
  date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  status appointment_status_enum DEFAULT 'SCHEDULED',
  created_by UUID,
  notes TEXT,
  created_at TIMESTAMP DEFAULT NOW(),

  FOREIGN KEY (doctor_id) REFERENCES doctors(id),
  FOREIGN KEY (patient_id) REFERENCES patients(id),
  FOREIGN KEY (created_by) REFERENCES users(id)
);

-- PREVENCIÓN DOBLE ASIGNACIÓN
CREATE UNIQUE INDEX unique_doctor_schedule
ON appointments (doctor_id, date, start_time);

CREATE INDEX idx_appointment_doctor_date
ON appointments (doctor_id, date);

CREATE TABLE appointment_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  appointment_id UUID NOT NULL,
  action TEXT NOT NULL,
  performed_by UUID,
  created_at TIMESTAMP DEFAULT NOW(),

  FOREIGN KEY (appointment_id) REFERENCES appointments(id),
  FOREIGN KEY (performed_by) REFERENCES users(id)
);

-- =========================
-- HISTORIAL CLÍNICO
-- =========================

CREATE TABLE medical_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  patient_id UUID NOT NULL,
  uploaded_by UUID,
  file_url TEXT NOT NULL,
  file_hash TEXT,
  source medical_record_source_enum,
  created_at TIMESTAMP DEFAULT NOW(),

  FOREIGN KEY (patient_id) REFERENCES patients(id),
  FOREIGN KEY (uploaded_by) REFERENCES users(id)
);

CREATE INDEX idx_medical_record_patient
ON medical_records (patient_id);

CREATE TABLE risk_classifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  medical_record_id UUID UNIQUE NOT NULL,
  risk_level risk_level_enum,
  score NUMERIC,
  created_at TIMESTAMP DEFAULT NOW(),

  FOREIGN KEY (medical_record_id) REFERENCES medical_records(id)
);

-- =========================
-- TRATAMIENTOS
-- =========================

CREATE TABLE treatments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  patient_id UUID NOT NULL,
  doctor_id UUID NOT NULL,
  description TEXT NOT NULL,
  status treatment_status_enum DEFAULT 'ACTIVE',
  created_at TIMESTAMP DEFAULT NOW(),

  FOREIGN KEY (patient_id) REFERENCES patients(id),
  FOREIGN KEY (doctor_id) REFERENCES doctors(id)
);

CREATE INDEX idx_treatment_patient
ON treatments (patient_id);

CREATE TABLE treatment_approvals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  treatment_id UUID NOT NULL,
  approved_by UUID,
  notes TEXT,
  approved_at TIMESTAMP DEFAULT NOW(),

  FOREIGN KEY (treatment_id) REFERENCES treatments(id),
  FOREIGN KEY (approved_by) REFERENCES users(id)
);

CREATE TABLE medication_changes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  treatment_id UUID NOT NULL,
  previous_medication TEXT,
  new_medication TEXT,
  changed_by UUID,
  created_at TIMESTAMP DEFAULT NOW(),

  FOREIGN KEY (treatment_id) REFERENCES treatments(id),
  FOREIGN KEY (changed_by) REFERENCES users(id)
);

-- =========================
-- NOTIFICACIONES 
-- =========================

CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL,
  type notification_type_enum,
  message TEXT,
  status notification_status_enum DEFAULT 'PENDING',
  entity_type TEXT,
  entity_id UUID,
  sent_at TIMESTAMP,

  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- =========================
-- REPORTES 
-- =========================

CREATE TABLE reports (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  generated_by UUID,
  type report_type_enum,
  file_url TEXT,
  entity_type TEXT,
  entity_id UUID,
  created_at TIMESTAMP DEFAULT NOW(),

  FOREIGN KEY (generated_by) REFERENCES users(id)
);

-- =========================
-- DATA INICIAL
-- =========================

INSERT INTO roles (name) VALUES ('ADMIN'), ('DOCTOR');