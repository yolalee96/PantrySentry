const nodemailer = require('nodemailer');

const GMAIL_USER = process.env.GMAIL_USER; // e.g. yourname@gmail.com
const GMAIL_APP_PASSWORD = process.env.GMAIL_APP_PASSWORD; // 16-char App Password, NOT your normal Gmail password
const FRONTEND_URL = process.env.FRONTEND_URL; // e.g. https://pantrybuddy-yourname.vercel.app

let transporter = null;
if (GMAIL_USER && GMAIL_APP_PASSWORD) {
  transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: { user: GMAIL_USER, pass: GMAIL_APP_PASSWORD },
  });
} else {
  console.error('GMAIL_USER / GMAIL_APP_PASSWORD not set — password reset emails will be logged, not sent. See README "Email (Gmail SMTP)".');
}

/**
 * Sends a password-reset email with a link back to the Flutter app, via
 * your own Gmail account. Unlike a third-party email API's sandbox mode,
 * this has NO restriction on which recipient it can send to — it works
 * for any user's email address, not just your own, once GMAIL_USER and
 * GMAIL_APP_PASSWORD are set correctly. See README "Email (Gmail SMTP)"
 * for how to generate an App Password.
 */
async function sendPasswordResetEmail(toEmail, resetToken) {
  const resetLink = `${FRONTEND_URL}/#/reset-password?token=${encodeURIComponent(resetToken)}`;

  if (!transporter) {
    // No Gmail credentials configured — fail safe by logging instead of
    // crashing, so local dev without Gmail set up still "works" (just
    // doesn't send anything real).
    console.log(`[password reset email — not sent, Gmail not configured] Would send to ${toEmail}: ${resetLink}`);
    return;
  }

  await transporter.sendMail({
    from: `"PantryBuddy" <${GMAIL_USER}>`,
    to: toEmail,
    subject: 'Reset your PantryBuddy password',
    html: `
      <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto;">
        <h2 style="color: #2E7D4F;">Reset your password</h2>
        <p>We received a request to reset your PantryBuddy password. Click the button below to choose a new one — this link expires in 30 minutes.</p>
        <p style="text-align: center; margin: 32px 0;">
          <a href="${resetLink}" style="background: #2E7D4F; color: white; padding: 12px 28px; border-radius: 8px; text-decoration: none; font-weight: bold;">Reset Password</a>
        </p>
        <p style="color: #888; font-size: 13px;">If you didn't request this, you can safely ignore this email.</p>
      </div>
    `,
  });
}

module.exports = { sendPasswordResetEmail };
