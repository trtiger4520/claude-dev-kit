using BenchmarkApp.Contracts;
using BenchmarkApp.Domain;
using BenchmarkApp.Infrastructure;
using BenchmarkApp.Mapping;

namespace BenchmarkApp.Application;

public sealed class LoginHandler(UserRepository repository, UserAuthenticator authenticator, AuditLog auditLog)
{
    public UserDto Handle(LoginCommand command)
    {
        ValidationBehavior.Validate(command);
        var user = repository.FindByEmail(command.Email) ?? throw new InvalidOperationException("User not found");
        if (!authenticator.Verify(user, command.Password))
        {
            throw new UnauthorizedAccessException();
        }

        auditLog.RecordLogin(user.Id);
        return UserMapper.Map(user);
    }
}
