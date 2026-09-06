import { ScanLine } from "lucide-react";
import { login } from "./actions";

const ERROR_MESSAGES: Record<string, string> = {
  invalid_credentials: "The email or password is incorrect.",
  no_organization: "This account does not have an active nexaIQ workspace.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  const errorMessage = error ? ERROR_MESSAGES[error] : undefined;

  return (
    <main className="grid min-h-screen place-items-center p-5">
      <section className="w-full max-w-md rounded-2xl border border-white/8 bg-slate-900/80 p-7 shadow-2xl">
        <div className="mb-7 flex items-center gap-3">
          <span className="grid size-11 place-items-center rounded-xl bg-cyan-300/10 text-cyan-200"><ScanLine /></span>
          <div><h1 className="text-2xl font-extrabold">nexa<span className="text-cyan-300">IQ</span></h1><p className="text-sm text-slate-500">Secure workspace access</p></div>
        </div>
        {errorMessage && <p role="alert" className="mb-4 rounded-lg border border-amber-300/25 bg-amber-300/8 px-3 py-2 text-sm text-amber-100">{errorMessage}</p>}
        <form className="space-y-4">
          <label className="block text-sm font-medium">Email<input className="mt-2 min-h-11 w-full rounded-lg border border-white/10 bg-black/20 px-3 outline-none focus:border-cyan-300/50" name="email" type="email" autoComplete="email" required /></label>
          <label className="block text-sm font-medium">Password<input className="mt-2 min-h-11 w-full rounded-lg border border-white/10 bg-black/20 px-3 outline-none focus:border-cyan-300/50" name="password" type="password" autoComplete="current-password" required /></label>
          <button className="min-h-11 w-full rounded-lg bg-cyan-300 px-4 font-bold text-slate-950" formAction={login}>Sign in</button>
        </form>
        <p className="mt-5 text-xs leading-relaxed text-slate-500">Accounts are provisioned by an administrator. Access is organization-scoped. AI-assisted findings require professional review.</p>
      </section>
    </main>
  );
}
