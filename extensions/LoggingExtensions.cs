using System.IO;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.Extensions.Configuration;

namespace SampleApp.Extensions;

public static class LoggingExtensions
{
    public static ILoggingBuilder AddFileLogger(this ILoggingBuilder builder, IConfiguration configuration)
    {
        var loggingSection = configuration.GetSection("Logging:File");
        if (!loggingSection.Exists())
        {
            return builder;
        }
        
        string logFilePath = loggingSection["Path"] ?? "logs/app.log";
        bool append = loggingSection.GetValue("Append", true);
        long fileSizeLimit = loggingSection.GetValue("FileSizeLimitBytes", 10 * 1024 * 1024); // Default 10MB
        int maxRollingFiles = loggingSection.GetValue("MaxRollingFiles", 10);
        
        // Ensure the directory exists
        string logDirectory = Path.GetDirectoryName(logFilePath) ?? "logs";
        if (!Directory.Exists(logDirectory))
        {
            Directory.CreateDirectory(logDirectory);
        }
        
        return builder.AddFile(options =>
        {
            options.LogDirectory = logDirectory;
            options.FileName = Path.GetFileName(logFilePath);
            options.Extension = "";  // Extension is already included in FileName
            options.FileSizeLimit = fileSizeLimit;
            options.RetainedFileCountLimit = maxRollingFiles;
            options.Append = append;
        });
    }
    
    // Simple file logger provider implementation
    private static ILoggingBuilder AddFile(this ILoggingBuilder builder, Action<FileLoggerOptions> configure)
    {
        builder.Services.AddSingleton<ILoggerProvider, FileLoggerProvider>();
        builder.Services.Configure(configure);
        return builder;
    }
}

public class FileLoggerOptions
{
    public string LogDirectory { get; set; } = "logs";
    public string FileName { get; set; } = "app-{Date}.log";
    public string Extension { get; set; } = "";
    public long FileSizeLimit { get; set; } = 10 * 1024 * 1024; // 10MB
    public int RetainedFileCountLimit { get; set; } = 10;
    public bool Append { get; set; } = true;
}

public class FileLoggerProvider : ILoggerProvider
{
    private readonly FileLoggerOptions _options;
    
    public FileLoggerProvider(IOptions<FileLoggerOptions> options)
    {
        _options = options.Value;
        
        // Ensure directory exists
        if (!Directory.Exists(_options.LogDirectory))
        {
            Directory.CreateDirectory(_options.LogDirectory);
        }
    }
    
    public ILogger CreateLogger(string categoryName)
    {
        return new FileLogger(categoryName, _options);
    }
    
    public void Dispose()
    {
        // Nothing to dispose
    }
}

public class FileLogger : ILogger
{
    private readonly string _categoryName;
    private readonly FileLoggerOptions _options;
    private readonly object _lock = new object();
    
    public FileLogger(string categoryName, FileLoggerOptions options)
    {
        _categoryName = categoryName;
        _options = options;
    }
    
    public IDisposable? BeginScope<TState>(TState state) where TState : notnull
    {
        return NullScope.Instance;
    }
    
    public bool IsEnabled(LogLevel logLevel)
    {
        return logLevel != LogLevel.None;
    }
    
    public void Log<TState>(
        LogLevel logLevel,
        EventId eventId,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        if (!IsEnabled(logLevel))
        {
            return;
        }
        
        var logFileName = _options.FileName.Replace("{Date}", DateTime.Now.ToString("yyyyMMdd"));
        var fullPath = Path.Combine(_options.LogDirectory, logFileName + _options.Extension);
        
        var logRecord = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] [{logLevel}] [{_categoryName}] {formatter(state, exception)}";
        if (exception != null)
        {
            logRecord += Environment.NewLine + exception;
        }
        
        lock (_lock)
        {
            // Check file size and roll if necessary
            if (File.Exists(fullPath))
            {
                var fileInfo = new FileInfo(fullPath);
                if (fileInfo.Length > _options.FileSizeLimit)
                {
                    RollFile(fullPath);
                }
            }
            
            File.AppendAllText(fullPath, logRecord + Environment.NewLine);
        }
    }
    
    private void RollFile(string filePath)
    {
        // Simple rolling implementation
        for (int i = _options.RetainedFileCountLimit - 1; i >= 1; i--)
        {
            var sourceFileName = filePath + "." + (i - 1);
            var destFileName = filePath + "." + i;
            
            if (File.Exists(sourceFileName))
            {
                if (File.Exists(destFileName))
                {
                    File.Delete(destFileName);
                }
                File.Move(sourceFileName, destFileName);
            }
        }
        
        // Move the current file
        var backupFilePath = filePath + ".1";
        if (File.Exists(backupFilePath))
        {
            File.Delete(backupFilePath);
        }
        File.Move(filePath, backupFilePath);
    }
    
    private class NullScope : IDisposable
    {
        public static NullScope Instance { get; } = new NullScope();
        
        private NullScope() { }
        
        public void Dispose() { }
    }
}