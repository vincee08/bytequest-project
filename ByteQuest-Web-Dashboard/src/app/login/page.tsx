import { AuthLayout } from "@/components/auth/AuthLayout";
import { AuthCard } from "@/components/auth/AuthCard";
import { AuthBrand } from "@/components/auth/AuthBrand";
import { LoginForm } from "@/components/auth/LoginForm";
import { LoginIllustration } from "@/components/auth/LoginIllustration";

const LOGIN_NOTICES: Record<string, string> = {
  session_timeout:
    "ByteQuest took too long to confirm your session. Wait a moment, then sign in again.",
  account_inactive: "This account is not active. Contact a ByteQuest administrator.",
  staff_only:
    "This dashboard is for Instructor and Admin accounts. Learners use the ByteQuest mobile app.",
  configuration: "Sign-in is unavailable because the dashboard is not configured.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { error } = await searchParams;
  const notice = typeof error === "string" ? LOGIN_NOTICES[error] : undefined;
  return (
    <AuthLayout illustration={<LoginIllustration />} light>
      <AuthCard compact>
        <AuthBrand
          title="Sign in to ByteQuest"
          subtitle="Secure access for Instructor and Admin accounts"
          centered
        />
        {notice ? (
          <p
            role="alert"
            className="mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950"
          >
            {notice}
          </p>
        ) : null}
        <LoginForm />
      </AuthCard>
    </AuthLayout>
  );
}
