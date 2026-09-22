// Vercel's Node.js runtime treats any exported Express app as a
// request handler directly — no app.listen() needed here. See
// vercel.json's rewrites for how every request path gets routed here.
module.exports = require('../src/app');
