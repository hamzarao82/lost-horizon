// Static export for GitHub Pages. The site is served at https://<user>.github.io/<repo>/,
// so the CI sets NEXT_PUBLIC_BASE_PATH=/<repo>. Leave it empty for local `npm run dev`.
const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  trailingSlash: true,
  basePath,
  assetPrefix: basePath || undefined,
  images: { unoptimized: true },
  eslint: { ignoreDuringBuilds: true },
  poweredByHeader: false,
};

export default nextConfig;
