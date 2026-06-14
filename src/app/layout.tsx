import type { Metadata } from "next";
import { Figtree, Newsreader } from "next/font/google";
import { Providers } from "@/components/providers";
import "./globals.css";

const figtree = Figtree({ subsets: ["latin"], variable: "--font-sans" });
const newsreader = Newsreader({ subsets: ["latin"], variable: "--font-display" });

export const metadata: Metadata = {
  title: "Diempool",
  description: "Supply DIEM on Base and earn USDC from pooled Venice inference demand.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="theme-light" suppressHydrationWarning>
      <body className={`${figtree.variable} ${newsreader.variable}`}>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
