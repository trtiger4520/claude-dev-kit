using BenchmarkApp.Domain;

namespace BenchmarkApp.Infrastructure;

public sealed class UserRepository
{
    public User? FindByEmail(string email) => email == "tiger@example.test"
        ? new User("u-1", "Tiger", "TR Tiger", email, "benchmark-password")
        : null;
}
