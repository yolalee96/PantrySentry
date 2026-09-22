// Local development entry point only — run with `npm start`.
// On Vercel, api/index.js imports app.js directly instead (Vercel's own
// infrastructure handles listening for requests; a serverless function
// never calls app.listen() itself).
const app = require('./app');

const port = Number(process.env.PORT) || 4000;
app.listen(port, () => {
  console.log(`PantryBuddy API listening on http://localhost:${port}`);
});
