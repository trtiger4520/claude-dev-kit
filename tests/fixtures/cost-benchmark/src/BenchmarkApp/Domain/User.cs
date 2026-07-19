namespace BenchmarkApp.Domain;

public sealed record User(string Id, string Name, string ProfileName, string Email, string PasswordHash);
