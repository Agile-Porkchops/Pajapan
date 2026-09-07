using Microsoft.AspNetCore.Diagnostics;

namespace Pajapan.Api.Infrastructure;

/// Turns the UnauthorizedAccessException that CurrentUser throws — no sub claim,
/// or a blocked user — into a 401 rather than a 500 with a stack trace.
///
/// Only that exception. Everything else is deliberately left unhandled so it keeps
/// propagating to the developer exception page in Development, which the endpoint
/// tests read to find out why a request failed.
public sealed class UnauthorizedExceptionHandler(ILogger<UnauthorizedExceptionHandler> log)
    : IExceptionHandler
{
    public ValueTask<bool> TryHandleAsync(HttpContext ctx, Exception ex, CancellationToken ct)
    {
        if (ex is not UnauthorizedAccessException) return ValueTask.FromResult(false);

        // Constraint 9: caught, logged and surfaced — never swallowed.
        log.LogWarning(ex, "Rejecting {Method} {Path} as unauthorized.",
            ctx.Request.Method, ctx.Request.Path);

        // Status only. The reason ("User is blocked") is for our logs, not the caller.
        ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
        return ValueTask.FromResult(true);
    }
}
