using BenchmarkApp.Contracts;
using BenchmarkApp.Domain;

namespace BenchmarkApp.Mapping;

public static class UserMapper
{
    public static UserDto Map(User user) => new(user.Id, user.Name);
}
