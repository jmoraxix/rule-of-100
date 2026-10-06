import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Rule of 100",
  description: "One action, 100 units a day, for 100 days.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
