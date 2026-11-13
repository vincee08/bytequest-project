"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
export function RecoveryForm() {
  const started = useRef(false);
  const [token, setToken] = useState("");
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [done, setDone] = useState(false);
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    const hash = new URLSearchParams(window.location.hash.slice(1));
    const value =
      hash.get("type") === "recovery" ? hash.get("token_hash") : null;
    // Keep credentials out of history, server request logs and referrers.
    window.history.replaceState(null, "", window.location.pathname);
    if (value) {
      setToken(value);
      return;
    }
    void fetch("/api/auth/recovery", { cache: "no-store" })
      .then((r) => r.json())
      .then((d) => {
        if (d.ready) setReady(true);
        else setError("Open a fresh recovery email to continue.");
      })
      .catch(() => setError("Recovery is temporarily unavailable. Try again."));
  }, []);
  async function call(body: object) {
    const response = await fetch("/api/auth/recovery", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const data = await response.json();
    if (!response.ok) throw Error(data.error);
    return data;
  }
  return (
    <div className="space-y-5">
      <p className="text-sm text-muted-foreground">
        {done
          ? "Your password was updated. Return to ByteQuest and sign in again. Learners use the mobile app."
          : ready
            ? "Choose a unique password with at least 12 characters."
            : "Confirm the recovery link from your email to choose a new password."}
      </p>
      {error ? (
        <p
          role="alert"
          className="rounded-md border border-destructive p-3 text-sm text-destructive"
        >
          {error}
        </p>
      ) : null}
      {!ready && !done && token ? (
        <Button
          className="min-h-12 w-full"
          disabled={busy}
          onClick={async () => {
            setBusy(true);
            setError("");
            try {
              await call({ action: "verify", token_hash: token });
              setToken("");
              setReady(true);
            } catch (e) {
              setError(e instanceof Error ? e.message : "Recovery failed.");
            } finally {
              setBusy(false);
            }
          }}
        >
          {busy ? "Verifying…" : "Continue securely"}
        </Button>
      ) : null}
      {ready && !done ? (
        <form
          className="space-y-4"
          onSubmit={async (e) => {
            e.preventDefault();
            if (busy) return;
            if (password !== confirm) {
              setError("The password confirmation does not match.");
              return;
            }
            setBusy(true);
            setError("");
            try {
              await call({ action: "update", password });
              setPassword("");
              setConfirm("");
              setReady(false);
              setDone(true);
            } catch (e) {
              setError(
                e instanceof Error ? e.message : "Password update failed.",
              );
            } finally {
              setBusy(false);
            }
          }}
        >
          <div className="space-y-2">
            <Label htmlFor="recovery-password">New password</Label>
            <Input
              className="min-h-12"
              id="recovery-password"
              type="password"
              autoComplete="new-password"
              minLength={12}
              maxLength={128}
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="recovery-confirm">Confirm password</Label>
            <Input
              className="min-h-12"
              id="recovery-confirm"
              type="password"
              autoComplete="new-password"
              minLength={12}
              maxLength={128}
              required
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
            />
          </div>
          <Button className="min-h-12 w-full" disabled={busy}>
            {busy ? "Updating password…" : "Update password"}
          </Button>
        </form>
      ) : null}
      <Link
        className="inline-flex min-h-12 items-center text-sm font-semibold text-primary"
        href="/login"
      >
        Return to sign in
      </Link>
    </div>
  );
}
