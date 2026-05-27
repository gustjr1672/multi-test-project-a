using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace Data.Application;

public interface IUserRepository
{
    Task<string?> GetUserNameByIdAsync(int id);
}

public class UserRepository : IUserRepository
{
    private readonly string _connectionString;

    public UserRepository(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("DefaultConnection");
    }

    public async Task<string?> GetUserNameByIdAsync(int id)
    {
        using var connection = new SqlConnection(_connectionString);

        // 쿼리 작성 (문자열 결합이 아닌 @Id 파라미터 사용)
        string sql = "SELECT name FROM [users] WHERE id = @Id";

        // Dapper가 내부적으로 SqlParameter를 생성하여 안전하게 바인딩해 줍니다.
        var name = await connection.QueryFirstOrDefaultAsync<string>(sql, new { Id = id });

        return name;
    }
}