// utils/tuyaSafe.js
const { TuyaContext } = require('@tuya/tuya-connector-nodejs');

function mask(v){ if(!v) return '(empty)'; const s=String(v); return s.length<=4?'****':s.slice(0,2)+'***'+s.slice(-2); }

// เก็บไว้ระดับ process
let __ctx = null;

function buildTuyaContextWithDebug(source='server'){
  if (__ctx) return __ctx;  // <-- กัน init ซ้ำ

  const baseUrl=(process.env.TUYA_BASE_URL||'').trim();
  const ak=(process.env.TUYA_ACCESS_ID||process.env.TUYA_AK||'').trim();
  const sk=(process.env.TUYA_ACCESS_SECRET||process.env.TUYA_SK||'').trim();

  if(!baseUrl||!ak||!sk){
    console.warn('⚠️ Tuya not configured',
      { baseUrl, ak:`AK=${mask(ak)}`, sk:`SK=${mask(sk)}` });
    __ctx = { __kind:'NO_OP_TUYA', async request(){ return { success:false, code:'TUYA_NOT_CONFIGURED' }; } };
    return __ctx;
  }

  console.log(`✅ Tuya context init by [${source}] @ ${baseUrl}`);
  const ctx = new TuyaContext({ baseUrl, accessKey: ak, secretKey: sk });
  const raw = ctx.request.bind(ctx);
  ctx.request = async (req) => {
    try {
      return await raw(req);
    } catch (e) {
      console.error(`[${source}] Tuya.request ERROR:`, e?.response?.data || e?.message || e);
      throw e;
    }
  };

  __ctx = ctx;
  return __ctx;
}

module.exports = { buildTuyaContextWithDebug };
