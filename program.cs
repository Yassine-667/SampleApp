var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHealthChecks();
builder.Services.AddProblemDetails(); // New in .NET 9 - improved problem details

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler();  // Uses the problem details middleware
    app.UseStatusCodePages();
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

// Add a minimal API endpoint (new in .NET 9)
app.MapGet("/api/version", () => new { Version = "1.0.0", Framework = ".NET 9", Timestamp = DateTime.UtcNow })
   .WithName("GetVersion");

app.Run();