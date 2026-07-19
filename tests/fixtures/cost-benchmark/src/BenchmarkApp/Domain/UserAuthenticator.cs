namespace BenchmarkApp.Domain;

public sealed class UserAuthenticator
{
    public bool Verify(User user, string password) => user.PasswordHash == password;
}
