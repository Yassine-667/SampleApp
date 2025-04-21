using SampleApp.Extensions;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHealthChecks();
builder.Services.AddProblemDetails(); // New in .NET 9 - improved problem details

// Add file logger
builder.Logging.AddFileLogger(builder.Configuration);

// Configure IIS integration
builder.Services.Configure<IISServerOptions>(options =>
{
    options.AutomaticAuthentication = false;
    options.MaxRequestBodySize = 52428800; // 50MB in bytes
});

// Configure forwarded headers for proxy scenarios
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedFor | 
                               Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedProto;
});

// Add CORS policy if needed
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowLocalhost", policy =>
    {
        policy.WithOrigins("http://localhost:8080", "https://localhost:8080")
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

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
    app.UseHsts();
}

// Use forwarded headers
app.UseForwardedHeaders();

// Use CORS
app.UseCors("AllowLocalhost");

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

// Add a minimal API endpoint (new in .NET 9)
app.MapGet("/api/version", () => new { Version = "1.0.0", Framework = ".NET 9", Timestamp = DateTime.UtcNow })
   .WithName("GetVersion");

// Add a simple ping endpoint that's useful for deployment verification
app.MapGet("/ping", () => "pong")
   .WithName("Ping");

app.Run();