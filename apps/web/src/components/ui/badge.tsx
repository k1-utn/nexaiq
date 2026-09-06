import * as React from "react";
import { cn } from "@/lib/utils";

const variants = {
  cyan: "border-cyan-300/25 bg-cyan-300/10 text-cyan-200",
  amber: "border-amber-300/25 bg-amber-300/10 text-amber-100",
  rose: "border-rose-300/25 bg-rose-300/10 text-rose-100",
  slate: "border-white/10 bg-white/5 text-slate-300",
  green: "border-emerald-300/25 bg-emerald-300/10 text-emerald-100",
} as const;

export function Badge({ variant = "slate", className, ...props }: React.ComponentProps<"span"> & { variant?: keyof typeof variants }) {
  return <span className={cn("inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold", variants[variant], className)} {...props} />;
}
