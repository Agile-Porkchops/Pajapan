import type { ReactNode } from "react";
import { Navigate } from "react-router";
import { Button } from "@/components/ui/button";
import { ApiError } from "@/lib/apiClient";
import { type AppUserRole, useCurrentUser } from "./useCurrentUser";

interface RequireRoleProps {
  role: AppUserRole | AppUserRole[];
  children: ReactNode;
}

export function RequireRole({ role, children }: RequireRoleProps) {
  const { data: user, isLoading, error, refetch } = useCurrentUser();
  const allowed = Array.isArray(role) ? role : [role];

  if (isLoading) {
    return <p role="status">Loading…</p>;
  }

  if (error instanceof ApiError && error.status === 401) {
    return <Navigate to="/login" replace />;
  }

  if (error) {
    return (
      <div role="alert">
        <p>Couldn't load your account. {error.message}</p>
        <Button onClick={() => refetch()}>Retry</Button>
      </div>
    );
  }

  if (!user || !allowed.includes(user.role)) {
    return <p>You don't have access to this page.</p>;
  }

  return <>{children}</>;
}
