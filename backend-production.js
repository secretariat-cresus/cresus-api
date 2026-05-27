const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const dotenv = require('dotenv');
const winston = require('winston');

dotenv.config();

const app = express();

// Logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' })
  ]
});

// Middleware
app.use(cors());
app.use(express.json());

// Database Pool
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Health Check
app.get('/api/health', (req, res) => {
  logger.info('Health check');
  res.json({ status: 'ok', timestamp: new Date() });
});

// 1. GET Plan utilisateur
app.get('/api/plan/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    logger.info(`Fetching plan for user ${userId}`);
    
    const result = await pool.query(
      'SELECT * FROM plans WHERE user_id = $1',
      [userId]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Plan not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error) {
    logger.error(`Error fetching plan: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// 2. GET Créanciers
app.get('/api/creditors/:planId', async (req, res) => {
  try {
    const { planId } = req.params;
    logger.info(`Fetching creditors for plan ${planId}`);
    
    const result = await pool.query(
      'SELECT * FROM creditors WHERE plan_id = $1',
      [planId]
    );
    
    res.json(result.rows);
  } catch (error) {
    logger.error(`Error fetching creditors: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// 3. POST Créer un paiement
app.post('/api/payments', async (req, res) => {
  try {
    const { userId, creditorId, amount, paymentDate } = req.body;
    
    if (!userId || !creditorId || !amount) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    
    logger.info(`Creating payment for user ${userId}`);
    
    const result = await pool.query(
      'INSERT INTO payments (user_id, creditor_id, amount, payment_date, status) VALUES ($1, $2, $3, $4, $5) RETURNING *',
      [userId, creditorId, amount, paymentDate, 'completed']
    );
    
    res.json(result.rows[0]);
  } catch (error) {
    logger.error(`Error creating payment: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// 4. GET Historique des paiements
app.get('/api/payments/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    logger.info(`Fetching payments for user ${userId}`);
    
    const result = await pool.query(
      'SELECT p.*, c.name FROM payments p JOIN creditors c ON p.creditor_id = c.id WHERE p.user_id = $1 ORDER BY p.payment_date DESC',
      [userId]
    );
    
    res.json(result.rows);
  } catch (error) {
    logger.error(`Error fetching payments: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// 5. GET Alertes paiements à venir
app.get('/api/alerts/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    logger.info(`Fetching alerts for user ${userId}`);
    
    const result = await pool.query(`
      SELECT c.name, c.monthly_payment, 
             (SELECT MAX(payment_date) FROM payments WHERE creditor_id = c.id) as last_payment
      FROM creditors c
      JOIN plans p ON c.plan_id = p.id
      WHERE p.user_id = $1
    `, [userId]);
    
    const alerts = result.rows.map(row => ({
      creditor: row.name,
      amount: row.monthly_payment,
      daysUntilPayment: Math.ceil((new Date(row.last_payment).getTime() + 30*24*60*60*1000 - Date.now()) / (24*60*60*1000))
    }));
    
    res.json(alerts);
  } catch (error) {
    logger.error(`Error fetching alerts: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// 6. POST Chat IA
app.post('/api/chat', async (req, res) => {
  try {
    const { message, userId } = req.body;
    
    if (!message) {
      return res.status(400).json({ error: 'Message required' });
    }
    
    logger.info(`Chat message from user ${userId}: ${message}`);
    
    // Appeler Claude API
    const claudeResponse = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.CLAUDE_API_KEY
      },
      body: JSON.stringify({
        model: 'claude-opus-4-20250805',
        max_tokens: 500,
        messages: [
          { role: 'user', content: `Tu es un assistant financier pour CRÉSUS, un organisme d'aide aux personnes en surendettement. Réponds à cette question: ${message}` }
        ]
      })
    });
    
    const data = await claudeResponse.json();
    const reply = data.content[0].text;
    
    // Sauvegarder la conversation
    await pool.query(
      'INSERT INTO conversations (user_id, message, reply) VALUES ($1, $2, $3)',
      [userId, message, reply]
    );
    
    res.json({ reply });
  } catch (error) {
    logger.error(`Error in chat: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// 7. POST Envoyer notification
app.post('/api/notifications/send', async (req, res) => {
  try {
    const { userId, type, message } = req.body;
    
    logger.info(`Sending notification to user ${userId}`);
    
    // Sauvegarder en BD
    const result = await pool.query(
      'INSERT INTO notifications (user_id, type, message) VALUES ($1, $2, $3) RETURNING *',
      [userId, type, message]
    );
    
    // Envoyer via Twilio (SMS) ou Firebase (Push)
    // À implémenter selon vos préférences
    
    res.json(result.rows[0]);
  } catch (error) {
    logger.error(`Error sending notification: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// 8. GET Statistiques utilisateur
app.get('/api/stats/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    
    const paymentsResult = await pool.query(
      'SELECT COUNT(*) as total, SUM(amount) as amount FROM payments WHERE user_id = $1 AND status = $2',
      [userId, 'completed']
    );
    
    const plansResult = await pool.query(
      'SELECT * FROM plans WHERE user_id = $1',
      [userId]
    );
    
    res.json({
      paymentsMade: paymentsResult.rows[0].total,
      amountPaid: paymentsResult.rows[0].amount,
      plan: plansResult.rows[0]
    });
  } catch (error) {
    logger.error(`Error fetching stats: ${error.message}`);
    res.status(500).json({ error: error.message });
  }
});

// 9. Error handling
app.use((err, req, res, next) => {
  logger.error(`Unhandled error: ${err.message}`);
  res.status(500).json({ error: 'Internal server error' });
});

// 10. Start server
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  logger.info(`🚀 CRÉSUS API running on port ${PORT}`);
  console.log(`🚀 CRÉSUS API running on port ${PORT}`);
});
