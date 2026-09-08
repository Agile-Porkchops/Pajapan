import { createBrowserRouter } from "react-router";

// Placeholders only. Catalog is built in M2, login in M0-06, admin in M1.
export const router = createBrowserRouter([
  { path: "/", element: <div>Catalog</div> },
  { path: "/login", element: <div>Login</div> },
  { path: "/admin", element: <div>Admin</div> },
]);
