import { randomUUID } from "node:crypto";
import {
  mkdirSync,
  renameSync,
  rmdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import type { Bridge } from "./bridge.ts";

// Antigravity 的后台 shell 可读取任务目录，默认沙箱会隔离命名管道。
export function backgroundWait(bridge: Bridge) {
  const files = new Set<string>();
  const timers = new Set<ReturnType<typeof setInterval>>();
  const quote = (s: string) => "'" + s.replaceAll("'", "''") + "'";
  return {
    close() {
      for (const timer of timers) clearInterval(timer);
      for (const file of files) {
        try {
          unlinkSync(file);
        } catch {}
        try {
          rmdirSync(join(file, ".."));
        } catch {}
      }
    },
    command(threadId: string, turnId: string) {
      const cwd = bridge.status(threadId).sessions[0].cwd;
      const dir = join(cwd, ".codex-bridge-wait");
      mkdirSync(dir, { recursive: true });
      const file = join(dir, randomUUID() + ".json");
      const pending = file + ".pending";
      writeFileSync(pending, "");
      files.add(pending);
      files.add(file);
      const check = () => {
        const state = bridge.status(threadId).sessions[0];
        if (
          state.lastTurnId === turnId &&
          state.status === "running" &&
          !state.questions.length
        )
          return;
        const terminal = bridge
          .events()
          .events.findLast(
            (e) => e.threadId === threadId && e.kind === state.status,
          );
        const result =
          state.lastTurnId !== turnId
            ? { status: "superseded", turnId }
            : state.questions.length
              ? { status: "waiting_input", questions: state.questions }
              : {
                  status: state.status,
                  answer: terminal?.text ?? state.lastAnswer,
                  truncated: terminal?.truncated ?? state.answerTruncated,
                };
        clearInterval(timer);
        timers.delete(timer);
        try {
          writeFileSync(file + ".tmp", JSON.stringify(result));
          renameSync(file + ".tmp", file);
        } catch (error) {
          console.error("写入 Codex 等待结果失败", error);
        } finally {
          try {
            unlinkSync(pending);
          } catch {}
        }
      };
      const timer = setInterval(check, 500);
      timers.add(timer);
      check();
      return [
        `$f=${quote(file)}`,
        `while (!(Test-Path -LiteralPath $f)) { if (!(Test-Path -LiteralPath ($f+'.pending')) -and !(Test-Path -LiteralPath $f)) { throw 'Codex bridge disconnected' }; Start-Sleep -Seconds 1 }`,
        "Get-Content -LiteralPath $f -Raw -Encoding UTF8",
      ].join("; ");
    },
  };
}
