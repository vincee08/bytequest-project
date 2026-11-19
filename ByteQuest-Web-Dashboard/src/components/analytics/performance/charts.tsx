"use client";

import { Bar, BarChart, CartesianGrid, Line, LineChart, XAxis, YAxis } from "recharts";
import { ChartContainer, ChartTooltip, ChartTooltipContent, type ChartConfig } from "@/components/ui/chart";
import { useReducedMotion } from "@/hooks/use-reduced-motion";
import { formatPercent, formatShortDay } from "@/lib/analytics/format";

const AXIS_TICK = { fontSize: 11 };

type TooltipValue = number | string | Array<number | string>;

function valueRow(config: ChartConfig, format: (value: number | null) => string) {
  return function ChartValueRow(value: TooltipValue, name: string | number) {
    const numeric = typeof value === "number" ? value : value === null ? null : Number(value);
    return (
      <div className="flex w-full items-center justify-between gap-4">
        <span className="text-muted-foreground">{config[String(name)]?.label ?? String(name)}</span>
        <span className="font-mono font-medium tabular-nums text-foreground">{format(Number.isFinite(numeric) ? numeric : null)}</span>
      </div>
    );
  };
}

const countFormat = (value: number | null) => (value === null ? "—" : String(value));

export const TREND_CONFIG = {
  assessments: { label: "Assessment submissions", color: "hsl(var(--chart-1))" },
  quizzes: { label: "Quiz submissions", color: "hsl(var(--chart-2))" },
  homework: { label: "Homework submissions", color: "hsl(var(--chart-4))" },
  practice_runs: { label: "Practice runs", color: "hsl(var(--chart-3))" },
  verified: { label: "Missions verified", color: "hsl(var(--chart-5))" },
} satisfies ChartConfig;

export function TrendLineChart({
  data,
  ariaLabel,
}: {
  data: Array<{ date: string } & Record<keyof typeof TREND_CONFIG, number>>;
  ariaLabel: string;
}) {
  const reducedMotion = useReducedMotion();
  return (
    <ChartContainer config={TREND_CONFIG} className="h-[300px] w-full aspect-auto" aria-label={ariaLabel} role="img">
      <LineChart data={data} margin={{ left: 8, right: 12, top: 8, bottom: 18 }} accessibilityLayer>
        <CartesianGrid vertical={false} strokeDasharray="3 3" />
        <XAxis dataKey="date" tickFormatter={formatShortDay} tickLine={false} axisLine={false} minTickGap={28} tick={AXIS_TICK}
          label={{ value: "Day (Asia/Manila)", position: "insideBottom", offset: -12, fontSize: 11 }} />
        <YAxis allowDecimals={false} tickLine={false} axisLine={false} width={40} tick={AXIS_TICK}
          label={{ value: "Events", angle: -90, position: "insideLeft", fontSize: 11 }} />
        <ChartTooltip content={<ChartTooltipContent labelFormatter={(_, payload) => formatShortDay(String(payload?.[0]?.payload?.date ?? ""))}
          formatter={valueRow(TREND_CONFIG, countFormat)} />} />
        {(Object.keys(TREND_CONFIG) as Array<keyof typeof TREND_CONFIG>).map((key, index) => (
          <Line key={key} type="monotone" dataKey={key} stroke={`var(--color-${key})`} strokeWidth={2}
            strokeDasharray={index % 2 ? "6 4" : undefined} dot={false} activeDot={{ r: 4 }} isAnimationActive={!reducedMotion} />
        ))}
      </LineChart>
    </ChartContainer>
  );
}

export function PercentBarChart({
  data,
  config,
  categoryKey,
  series,
  categoryLabel,
  valueLabel = "Percent (%)",
  ariaLabel,
  height = 280,
  layout = "horizontal",
}: {
  data: Array<Record<string, string | number | null>>;
  config: ChartConfig;
  categoryKey: string;
  series: string[];
  categoryLabel: string;
  valueLabel?: string;
  ariaLabel: string;
  height?: number;
  layout?: "horizontal" | "vertical";
}) {
  const reducedMotion = useReducedMotion();
  const vertical = layout === "vertical";
  return (
    <ChartContainer config={config} className="w-full aspect-auto" style={{ height }} aria-label={ariaLabel} role="img">
      <BarChart data={data} layout={vertical ? "vertical" : "horizontal"} margin={{ left: 8, right: 16, top: 8, bottom: 18 }} accessibilityLayer>
        <CartesianGrid vertical={vertical} horizontal={!vertical} strokeDasharray="3 3" />
        {vertical ? (
          <>
            <XAxis type="number" domain={[0, 100]} tickFormatter={(value) => `${value}%`} tickLine={false} axisLine={false} tick={AXIS_TICK}
              label={{ value: valueLabel, position: "insideBottom", offset: -12, fontSize: 11 }} />
            <YAxis type="category" dataKey={categoryKey} tickLine={false} axisLine={false} width={150} tick={AXIS_TICK} />
          </>
        ) : (
          <>
            <XAxis dataKey={categoryKey} tickLine={false} axisLine={false} tick={AXIS_TICK} interval={0}
              label={{ value: categoryLabel, position: "insideBottom", offset: -12, fontSize: 11 }} />
            <YAxis domain={[0, 100]} tickFormatter={(value) => `${value}%`} tickLine={false} axisLine={false} width={44} tick={AXIS_TICK}
              label={{ value: valueLabel, angle: -90, position: "insideLeft", fontSize: 11 }} />
          </>
        )}
        <ChartTooltip content={<ChartTooltipContent formatter={valueRow(config, formatPercent)} />} />
        {series.map((key) => (
          <Bar key={key} dataKey={key} fill={`var(--color-${key})`} radius={vertical ? [0, 4, 4, 0] : [4, 4, 0, 0]} maxBarSize={44}
            isAnimationActive={!reducedMotion} />
        ))}
      </BarChart>
    </ChartContainer>
  );
}

export function CountBarChart({
  data,
  config,
  categoryKey,
  series,
  categoryLabel,
  valueLabel,
  ariaLabel,
  stacked = false,
  height = 260,
}: {
  data: Array<Record<string, string | number | null>>;
  config: ChartConfig;
  categoryKey: string;
  series: string[];
  categoryLabel: string;
  valueLabel: string;
  ariaLabel: string;
  stacked?: boolean;
  height?: number;
}) {
  const reducedMotion = useReducedMotion();
  return (
    <ChartContainer config={config} className="w-full aspect-auto" style={{ height }} aria-label={ariaLabel} role="img">
      <BarChart data={data} margin={{ left: 8, right: 16, top: 8, bottom: 18 }} accessibilityLayer>
        <CartesianGrid vertical={false} strokeDasharray="3 3" />
        <XAxis dataKey={categoryKey} tickLine={false} axisLine={false} tick={AXIS_TICK} interval={0}
          label={{ value: categoryLabel, position: "insideBottom", offset: -12, fontSize: 11 }} />
        <YAxis allowDecimals={false} tickLine={false} axisLine={false} width={40} tick={AXIS_TICK}
          label={{ value: valueLabel, angle: -90, position: "insideLeft", fontSize: 11 }} />
        <ChartTooltip content={<ChartTooltipContent formatter={valueRow(config, countFormat)} />} />
        {series.map((key, index) => (
          <Bar key={key} dataKey={key} fill={`var(--color-${key})`} stackId={stacked ? "stack" : undefined}
            radius={stacked && index < series.length - 1 ? [0, 0, 0, 0] : [4, 4, 0, 0]} maxBarSize={48} isAnimationActive={!reducedMotion} />
        ))}
      </BarChart>
    </ChartContainer>
  );
}
