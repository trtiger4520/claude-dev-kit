namespace BenchmarkApp.Application;

public static class ValidationBehavior
{
    public static void Validate(LoginCommand command)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(command.Email);
        ArgumentException.ThrowIfNullOrWhiteSpace(command.Password);
    }
}
