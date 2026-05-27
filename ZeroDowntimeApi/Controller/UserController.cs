using Data.Application;
using Microsoft.AspNetCore.Mvc;

namespace ZeroDowntimeApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class UserController : ControllerBase
{
    private readonly IUserService _userService;

    public UserController(IUserService userService)
    {
        _userService = userService;
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> Get(int id, [FromQuery] int delay = 15)
    {
        var result = await _userService.GetFormattedUserNameAsync(id, delay);

        return Ok(new
        {
            Version = $"DEV {delay}초 지연 버전)",
            //Version = "V2 (즉시)",
            Message = "성공",
            UserId = id,
            Data = result
        });
    }

    [HttpGet("quick/{id:int}")]
    public async Task<IActionResult> GetQuick(int id)
    {
        var result = await _userService.GetFormattedUserNameQuick(id);

        return Ok(new
        {
            Version = "quick DEV (즉시)",
            Message = "성공",
            UserId = id,
            Data = result
        });
    }
}