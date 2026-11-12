import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  outputFileTracingRoot: process.cwd(),
  serverExternalPackages: ["pdfjs-dist"],
  outputFileTracingIncludes: {
    "/api/instructor/quizzes/ai-draft": [
      "./src/lib/resources/pdf-worker.mjs",
      "./node_modules/pdfjs-dist/**/*",
      // PDF.js loads these Node polyfills dynamically inside its worker.
      "./node_modules/.pnpm/@napi-rs+canvas*/node_modules/@napi-rs/**/*",
    ],
  },
  webpack: (config) => {
    if (process.env.NODE_ENV === "development") {
      config.module.rules.push({
        test: /\.(jsx|tsx)$/,
        exclude: /node_modules/,
        enforce: "pre",
        use: "@dyad-sh/nextjs-webpack-component-tagger",
      });
    }
    return config;
  },
};

export default nextConfig;
