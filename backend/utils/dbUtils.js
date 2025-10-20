// utils/dbUtils.js
const isPgPromise = (db) => typeof db.any === 'function';

async function withStatementTimeout(db, ms, run) {
  if (isPgPromise(db)) {
    return db.tx(async t => {
      await t.none('SET LOCAL statement_timeout = $1', [ms]);
      return run(t);
    });
  } else {
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      await client.query('SET LOCAL statement_timeout = $1', [ms]);
      const t = {
        any: (q, p=[]) => client.query(q, p).then(r => r.rows),
        one: (q, p=[]) => client.query(q, p).then(r => r.rows[0]),
        oneOrNone: (q,p=[]) => client.query(q,p).then(r=>r.rows[0]||null),
        none: (q,p=[]) => client.query(q,p).then(()=>{})
      };
      const out = await run(t);
      await client.query('COMMIT');
      return out;
    } catch (e) {
      try { await client.query('ROLLBACK'); } catch {}
      throw e;
    } finally {
      client.release();
    }
  }
}

module.exports = { withStatementTimeout, isPgPromise };
