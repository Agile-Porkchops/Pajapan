import { useQuery } from "@tanstack/react-query";
import { api, ApiError } from "@/lib/apiClient";

export type AppUserRole = "Customer" | "JapanBuyer" | "Fulfilment" | "Admin";

export interface CurrentUser {
  id: string;
  displayName: string;
  email: string;
  role: AppUserRole;
}

export function useCurrentUser() {
  return useQuery({
    queryKey: ["me"],
    queryFn: () => api<CurrentUser>("/api/me"),
    staleTime: 5 * 60 * 1000,
    // A 401 means "not signed in" -- retrying won't fix that, and retrying
    // would delay the login redirect for no reason. Other failures (the API
    // being down, a network error) get a couple of attempts before RequireRole
    // shows the error panel, so a blip doesn't immediately read as an outage.
    retry: (failureCount, error) =>
      !(error instanceof ApiError && error.status === 401) && failureCount < 2,
  });
}
