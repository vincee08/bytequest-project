import type { Metadata } from "next";
import { AuthLayout } from "@/components/auth/AuthLayout";
import { AuthCard } from "@/components/auth/AuthCard";
import { AuthBrand } from "@/components/auth/AuthBrand";
import { RecoveryForm } from "@/components/auth/RecoveryForm";
export const metadata: Metadata = {
  title: "Recover your password | ByteQuest",
  referrer: "no-referrer",
  robots: { index: false, follow: false },
};
export default function RecoverPage() {
  return (
    <AuthLayout centered>
      <AuthCard compact>
        <AuthBrand
          title="Recover your password"
          subtitle="Secure ByteQuest account recovery"
          centered
        />
        <RecoveryForm />
      </AuthCard>
    </AuthLayout>
  );
}
