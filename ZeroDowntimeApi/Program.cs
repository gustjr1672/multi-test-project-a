using Data.Application;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<HostOptions>(options =>
{
    options.ShutdownTimeout = TimeSpan.FromSeconds(65); // 도커(60초)보다 살짝 더 길게 설정
});

// 서비스에 헬스체크 추가
builder.Services.AddHealthChecks();
builder.Services.AddControllers();
builder.Services.AddRazorPages();

builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<IUserService, UserService>(); // 새로 추가됨!

var app = builder.Build();

// 헬스체크 엔드포인트 매핑 (/health 경로로 접근 시 Healthy 반환)
app.MapHealthChecks("/health");

app.MapControllers();
app.MapRazorPages();

// 버전 확인을 위한 간단한 API (Blue/Green 구분용)
//app.MapGet("/", () => "Hello! This is Version 16.0 (Blue)");
//app.MapGet("/", () => "Hello! This is Version 17.0 (Green)");

app.Run();