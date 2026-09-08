import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useNavigate } from "react-router";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { supabase } from "@/lib/supabase";

const schema = z.object({
  email: z.string().email("Enter a valid email address"),
  // Optional at the schema level so "email me a link" doesn't force a
  // password to be filled in first; password sign-in checks it explicitly.
  password: z.string().optional(),
});

type LoginForm = z.infer<typeof schema>;

export function LoginPage() {
  const navigate = useNavigate();
  const [serverError, setServerError] = useState<string | null>(null);
  const [magicLinkSent, setMagicLinkSent] = useState(false);
  const {
    register,
    handleSubmit,
    getValues,
    setError,
    formState: { errors, isSubmitting },
  } = useForm<LoginForm>({ resolver: zodResolver(schema) });

  const onPasswordSignIn = handleSubmit(async ({ email, password }) => {
    if (!password) {
      setError("password", { message: "Password is required" });
      return;
    }
    setServerError(null);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      // The server's own message, never a generic fallback -- "Invalid login
      // credentials" tells the user something actionable; "Something went
      // wrong" does not.
      setServerError(error.message);
      return;
    }
    navigate("/");
  });

  const onMagicLink = async () => {
    const email = getValues("email");
    const parsed = schema.shape.email.safeParse(email);
    if (!parsed.success) {
      setError("email", { message: parsed.error.issues[0].message });
      return;
    }
    setServerError(null);
    const { error } = await supabase.auth.signInWithOtp({ email });
    if (error) {
      setServerError(error.message);
      return;
    }
    setMagicLinkSent(true);
  };

  if (magicLinkSent) {
    return <p role="status">Check your email for a sign-in link.</p>;
  }

  return (
    <form onSubmit={onPasswordSignIn}>
      <label>
        Email
        <input type="email" autoComplete="email" {...register("email")} />
      </label>
      {errors.email && <p role="alert">{errors.email.message}</p>}

      <label>
        Password
        <input type="password" autoComplete="current-password" {...register("password")} />
      </label>
      {errors.password && <p role="alert">{errors.password.message}</p>}

      {serverError && <p role="alert">{serverError}</p>}

      <Button type="submit" disabled={isSubmitting}>
        Sign in
      </Button>
      <Button type="button" variant="outline" onClick={onMagicLink} disabled={isSubmitting}>
        Email me a sign-in link
      </Button>
    </form>
  );
}
