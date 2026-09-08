import { createBrowserRouter } from "react-router";
import { LoginPage } from "./features/auth/LoginPage";
import { RequireRole } from "./features/auth/RequireRole";

// Catalog placeholder -- built in M2.
export const router = createBrowserRouter([
  { path: "/", element: <div>Catalog</div> },
  { path: "/login", element: <LoginPage /> },
  {
    path: "/admin",
    element: (
      <RequireRole role="Admin">
        <div>Admin</div>
      </RequireRole>
    ),
  },
]);
