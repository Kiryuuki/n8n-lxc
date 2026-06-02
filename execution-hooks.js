console.log("=========================================");
console.log("EXT-HOOK: STARTING LOAD...");
console.log("=========================================");

const SUPABASE_URL = trimTrailingSlash(process.env.SUPABASE_URL || "");
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || "";
const LOG_TABLE = process.env.SUPABASE_EXECUTION_LOG_TABLE || "n8n_execution_logs";

const REDACT_PATTERNS = [
  { pattern: /EAA[A-Za-z0-9]{20,}/g, label: "FB_TOKEN" },
  {
    pattern: /"Authorization"\s*:\s*"Bearer\s+[^"]+"/gi,
    label: "BEARER_TOKEN",
    replacement: '"Authorization":"Bearer [REDACTED]"',
  },
  {
    pattern: /"access_token"\s*:\s*"[A-Za-z0-9\-._~+/]{20,}={0,2}"/gi,
    label: "ACCESS_TOKEN",
    replacement: '"access_token":"[REDACTED]"',
  },
  {
    pattern: /"page_access_token"\s*:\s*"[^"]{20,}"/gi,
    label: "PAGE_TOKEN",
    replacement: '"page_access_token":"[REDACTED]"',
  },
  {
    pattern: /"(apikey|api_key|x-api-key)"\s*:\s*"[^"]{16,}"/gi,
    label: "API_KEY",
    replacement: '"$1":"[REDACTED]"',
  },
];

// Redact known sensitive patterns from JSON-serializable hook data.
function sanitize(data) {
  if (data == null) return null;

  if (typeof data === "string") return redactString(data);

  const str = redactString(JSON.stringify(data));

  try {
    return JSON.parse(str);
  } catch {
    return { _sanitized: true, _error: "Failed to re-parse after redaction" };
  }
}

function redactString(value) {
  let str = value;

  for (const { pattern, label, replacement } of REDACT_PATTERNS) {
    const rep = replacement ?? `[REDACTED_${label}]`;
    str = str.replace(pattern, rep);
  }

  return str;
}

function trimTrailingSlash(value) {
  return value.replace(/\/+$/, "");
}

function toIso(value) {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function getExecutionId(run, fallback) {
  return String(fallback || run.executionId || run.id || run.data?.executionId || "");
}

function getStatus(run) {
  if (run.status) return String(run.status);
  return run.data?.resultData?.error ? "failed" : "success";
}

function getDurationMs(startedAt, finishedAt) {
  if (!startedAt || !finishedAt) return null;
  const duration = new Date(finishedAt).getTime() - new Date(startedAt).getTime();
  return Number.isFinite(duration) && duration >= 0 ? duration : null;
}

function buildLogData(run, workflowData, executionId) {
  const startedAt = toIso(run.startedAt) || new Date().toISOString();
  const finishedAt = toIso(run.stoppedAt) || new Date().toISOString();
  const nodeCount = Array.isArray(workflowData.nodes) ? workflowData.nodes.length : null;
  const errorMessage = run.data?.resultData?.error?.message
    ? redactString(String(run.data.resultData.error.message)).substring(0, 500)
    : null;

  return {
    execution_id: getExecutionId(run, executionId),
    workflow_id: String(workflowData.id || ""),
    workflow_name: String(workflowData.name || "Untitled workflow"),
    status: getStatus(run),
    finished: true,
    started_at: startedAt,
    finished_at: finishedAt,
    duration_ms: getDurationMs(startedAt, finishedAt),
    mode: run.mode ? String(run.mode) : null,
    node_count: nodeCount,
    error_message: errorMessage,
    // Full execution/workflow JSON can include raw node I/O and secrets.
    // If needed later, store only sanitized subsets with sanitize().
    // execution_data: sanitize(run.data?.resultData?.runData ?? null),
    // workflow_data: sanitize(workflowData ?? null),
  };
}

function buildReadyPingData() {
  const now = new Date().toISOString();

  return {
    execution_id: `hook-ready-${Date.now()}`,
    workflow_id: "system",
    workflow_name: "__hook_healthcheck",
    status: "success",
    finished: true,
    started_at: now,
    finished_at: now,
    duration_ms: 0,
    mode: "startup",
  };
}

async function sendToSupabase(logData) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${LOG_TABLE}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
      Prefer: "return=minimal",
    },
    body: JSON.stringify(logData),
  });

  if (!response.ok) {
    const body = await response.text();
    console.log(`[HOOK] SUPABASE ERROR ${response.status}: ${body}`);
    return false;
  }

  console.log(`[HOOK] SUCCESS: logged execution ${logData.execution_id}`);
  return true;
}

async function pingSupabase() {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    console.log("[HOOK] Supabase ping skipped - missing env vars");
    return;
  }

  try {
    const ok = await sendToSupabase(buildReadyPingData());
    console.log("[HOOK] Supabase ping:", ok ? "OK" : "FAILED");
  } catch (error) {
    console.log("[HOOK] Supabase ping failed:", error.message);
  }
}

module.exports = {
  n8n: {
    ready: [
      async function () {
        console.log("[HOOK] n8n IS READY AND HOOKS ARE ACTIVE");
        console.log("[HOOK] Supabase URL:", SUPABASE_URL ? "OK" : "MISSING");
        console.log("[HOOK] Supabase key:", SUPABASE_SERVICE_KEY ? "OK" : "MISSING");
        await pingSupabase();
      },
    ],
  },
  workflow: {
    postExecute: [
      async function (fullRunData, workflowData, executionId) {
        console.log(`[HOOK] WORKFLOW FINISHED: ${workflowData.name}`);

        if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
          console.log("[HOOK] Skipping Supabase - missing env vars");
          return;
        }

        try {
          const logData = buildLogData(fullRunData, workflowData, executionId);
          await sendToSupabase(logData);
        } catch (error) {
          console.log("[HOOK] FETCH ERROR:", error.message);
        }
      },
    ],
  },
};
