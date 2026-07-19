using BenchmarkApp.Domain;
using BenchmarkApp.Mapping;
using BenchmarkApp.Security;

var mode = args.SingleOrDefault() ?? "baseline";
var user = new User("u-1", "Tiger", "TR Tiger", "tiger@example.test", "benchmark-password");

switch (mode)
{
    case "baseline":
        if (UserMapper.Map(user).Name != "Tiger")
        {
            throw new InvalidOperationException("Baseline mapping failed");
        }
        break;
    case "dto":
        var dto = UserMapper.Map(user);
        var displayName = dto.GetType().GetProperty("DisplayName");
        if (displayName is null || (string?)displayName.GetValue(dto) != "TR Tiger")
        {
            throw new InvalidOperationException("UserDto.DisplayName must map from User.ProfileName");
        }
        break;
    case "auth":
        var requiredRole = typeof(AuthPolicy).GetField(nameof(AuthPolicy.RequiredRole))?.GetRawConstantValue() as string;
        if (requiredRole != AuthPolicy.Administrator)
        {
            throw new InvalidOperationException("AuthPolicy.RequiredRole must be Administrator");
        }
        break;
    default:
        throw new ArgumentOutOfRangeException(nameof(mode), mode, "Unknown benchmark check");
}

Console.WriteLine($"PASS: {mode}");
