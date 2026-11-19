import type { ReactNode } from "react";

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description: string;
  actions?: ReactNode;
}) {
  return (
    <header className="flex flex-col gap-4 border-b border-border/70 pb-5 sm:flex-row sm:items-end sm:justify-between lg:pb-6">
      {/* The title keeps a readable width; wide action groups wrap instead of squeezing it. */}
      <div className="min-w-0 sm:min-w-[16rem] sm:flex-1">
        <h1 className="text-[1.45rem] font-bold leading-tight tracking-[-0.035em] text-foreground sm:text-[1.55rem]">{title}</h1>
        <p className="mt-2 max-w-3xl text-[13px] leading-6 text-muted-foreground">{description}</p>
      </div>
      {actions ? <div className="flex w-full flex-wrap items-center gap-2 print-hidden sm:w-auto sm:max-w-[60%] sm:justify-end">{actions}</div> : null}
    </header>
  );
}
