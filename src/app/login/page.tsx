import LoginForm from "./login-form";

export default async function Page({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  return <LoginForm linkError={(await searchParams).error === "link"} />;
}
