-- ================================================================
-- DATABASE CRÉSUS - PRODUCTION
-- ================================================================

-- 1. TABLE UTILISATEURS
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  phone VARCHAR(20),
  name VARCHAR(255),
  password_hash VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. TABLE PLANS DE SURENDETTEMENT
CREATE TABLE plans (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total_amount DECIMAL(10, 2) NOT NULL,
  duration_months INT NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE,
  status VARCHAR(50) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. TABLE CRÉANCIERS
CREATE TABLE creditors (
  id SERIAL PRIMARY KEY,
  plan_id INT NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  monthly_payment DECIMAL(10, 2) NOT NULL,
  total_amount DECIMAL(10, 2) NOT NULL,
  creditor_type VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. TABLE PAIEMENTS
CREATE TABLE payments (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  creditor_id INT NOT NULL REFERENCES creditors(id) ON DELETE CASCADE,
  amount DECIMAL(10, 2) NOT NULL,
  payment_date DATE NOT NULL,
  status VARCHAR(50) DEFAULT 'pending',
  proof_url VARCHAR(500),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 5. TABLE NOTIFICATIONS
CREATE TABLE notifications (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(50),
  message TEXT,
  read BOOLEAN DEFAULT FALSE,
  sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. TABLE CONVERSATIONS
CREATE TABLE conversations (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  reply TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 7. TABLE LOGS
CREATE TABLE logs (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id),
  action VARCHAR(255),
  details TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ================================================================
-- INDEXES
-- ================================================================

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_plans_user ON plans(user_id);
CREATE INDEX idx_creditors_plan ON creditors(plan_id);
CREATE INDEX idx_payments_user ON payments(user_id);
CREATE INDEX idx_payments_creditor ON payments(creditor_id);
CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_conversations_user ON conversations(user_id);
CREATE INDEX idx_logs_user ON logs(user_id);
CREATE INDEX idx_logs_action ON logs(action);

-- ================================================================
-- DONNÉES INITIALES
-- ================================================================

-- Créer un utilisateur de test
INSERT INTO users (email, name, phone) VALUES
('demo@cresus.fr', 'Utilisateur Démo', '02 40 72 40 05');

-- Créer un plan de test
INSERT INTO plans (user_id, total_amount, duration_months, start_date, status) VALUES
(1, 28500, 47, '2026-01-01', 'active');

-- Créer des créanciers
INSERT INTO creditors (plan_id, name, monthly_payment, total_amount, creditor_type) VALUES
(1, 'Crédit automobile', 485, 10560, 'Auto'),
(1, 'Banque de France', 250, 7180, 'Bank'),
(1, 'Opérateur téléphone', 90, 3140, 'Telecom');

-- ================================================================
-- TRIGGERS
-- ================================================================

-- Mettre à jour updated_at automatiquement
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_users_timestamp
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trigger_plans_timestamp
BEFORE UPDATE ON plans
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trigger_creditors_timestamp
BEFORE UPDATE ON creditors
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trigger_payments_timestamp
BEFORE UPDATE ON payments
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

-- ================================================================
-- VIEWS
-- ================================================================

-- Vue : Résumé utilisateur
CREATE VIEW user_summary AS
SELECT 
  u.id,
  u.email,
  u.name,
  p.total_amount,
  p.duration_months,
  COUNT(DISTINCT c.id) as creditor_count,
  SUM(CASE WHEN py.status = 'completed' THEN py.amount ELSE 0 END) as total_paid,
  p.status
FROM users u
LEFT JOIN plans p ON u.id = p.user_id
LEFT JOIN creditors c ON p.id = c.plan_id
LEFT JOIN payments py ON u.id = py.user_id AND py.status = 'completed'
GROUP BY u.id, p.id;

-- Vue : Alertes à venir
CREATE VIEW upcoming_alerts AS
SELECT 
  u.id as user_id,
  c.id as creditor_id,
  c.name,
  c.monthly_payment,
  MAX(py.payment_date) as last_payment,
  (MAX(py.payment_date) + INTERVAL '30 days') as next_payment_date
FROM users u
JOIN plans p ON u.id = p.user_id
JOIN creditors c ON p.id = c.plan_id
LEFT JOIN payments py ON c.id = py.creditor_id
GROUP BY u.id, c.id;

-- ================================================================
-- FONCTIONS UTILES
-- ================================================================

-- Calculer le taux de progression
CREATE OR REPLACE FUNCTION get_completion_rate(user_id_param INT)
RETURNS NUMERIC AS $$
DECLARE
  total_amount DECIMAL;
  paid_amount DECIMAL;
BEGIN
  SELECT p.total_amount INTO total_amount
  FROM plans p WHERE p.user_id = user_id_param LIMIT 1;
  
  SELECT COALESCE(SUM(amount), 0) INTO paid_amount
  FROM payments WHERE user_id = user_id_param AND status = 'completed';
  
  IF total_amount = 0 THEN
    RETURN 0;
  END IF;
  
  RETURN (paid_amount / total_amount * 100)::NUMERIC(5,2);
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- PERMISSIONS
-- ================================================================

-- Créer un rôle d'application
CREATE ROLE cresus_app WITH LOGIN PASSWORD 'secure_password_here';

-- Donner les permissions
GRANT CONNECT ON DATABASE cresus_db TO cresus_app;
GRANT USAGE ON SCHEMA public TO cresus_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO cresus_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cresus_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO cresus_app;
