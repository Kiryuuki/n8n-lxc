console.log("=========================================");
console.log("EXT-HOOK: STARTING LOAD...");
console.log("=========================================");

const SUPABASE_URL = trimTrailingSlash(process.env.SUPABASE_URL || "");
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || "";
const LOG_TABLE = process.env.SUPABASE_EXECUTION_LOG_TABLE || "n8n_execution_logs";

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

  return {
    execution_id: getExecutionId(run, executionId),
    workflow_id: String(workflowData.id || ""),
    workflow_name: String(workflowData.name || "Untitled workflow"),
    status: getStatus(run),
    started_at: startedAt,
    finished_at: finishedAt,
    duration_ms: getDurationMs(startedAt, finishedAt),
    mode: run.mode ? String(run.mode) : null,
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
    return;
  }

  console.log(`[HOOK] SUCCESS: logged execution ${logData.execution_id}`);
}

module.exports = {
  n8n: {
    ready: [
      async function () {
        console.log("[HOOK] n8n IS READY AND HOOKS ARE ACTIVE");
        console.log("[HOOK] Supabase URL:", SUPABASE_URL ? "OK" : "MISSING");
        console.log("[HOOK] Supabase key:", SUPABASE_SERVICE_KEY ? "OK" : "MISSING");
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
