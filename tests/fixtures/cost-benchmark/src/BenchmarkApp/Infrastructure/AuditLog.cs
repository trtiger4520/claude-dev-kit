namespace BenchmarkApp.Infrastructure;

public sealed class AuditLog
{
    public void RecordLogin(string userId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(userId);
    }
}
