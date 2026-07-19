using BenchmarkApp.Application;
using BenchmarkApp.Contracts;

namespace BenchmarkApp.Web;

public sealed class LoginEndpoint(LoginHandler handler)
{
    public UserDto Post(string email, string password) => handler.Handle(new LoginCommand(email, password));
}
